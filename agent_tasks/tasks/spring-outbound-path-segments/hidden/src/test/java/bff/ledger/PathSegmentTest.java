package bff.ledger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriUtils;

class PathSegmentTest {
    private final AtomicReference<URI> sent = new AtomicReference<>();
    private MockRestServiceServer server;

    private LedgerClient client() {
        var builder = RestClient.builder().baseUrl("http://ledger.internal.test");
        server = MockRestServiceServer.bindTo(builder).ignoreExpectOrder(true).build();
        return new LedgerClient(builder.build(), "t0k3n");
    }

    @ParameterizedTest
    @ValueSource(strings = {"acc-1", "../admin/users", "a/b", "x?role=admin", "x#frag", "%2e%2e", "%2e%2e%2fadmin",
            "acc 1", "café", "..x", "x.."})
    void theIdStaysInsideOneSegment(String id) {
        var client = client();
        server.expect(request -> sent.set(request.getURI())).andRespond(withSuccess("[]", MediaType.APPLICATION_JSON));
        client.statements(id);
        URI uri = sent.get();
        assertEquals("ledger.internal.test", uri.getHost());
        assertEquals(null, uri.getRawQuery(), "query in " + uri);
        assertEquals(null, uri.getRawFragment(), "fragment in " + uri);
        List<String> segments = Arrays.asList(uri.getRawPath().split("/", -1));
        assertEquals(4, segments.size(), "segments of " + uri.getRawPath());
        assertEquals(List.of("", "accounts"), segments.subList(0, 2));
        assertEquals("statements", segments.get(3));
        assertEquals(id, UriUtils.decode(segments.get(2), StandardCharsets.UTF_8), "raw segment " + segments.get(2));
    }

    @ParameterizedTest
    @ValueSource(strings = {"..", ".", ""})
    void dotAndEmptySegmentsAreRejectedBeforeAnyRequest(String id) {
        var client = client();
        assertThrows(IllegalArgumentException.class, () -> client.statements(id));
        server.verify();   // no request was expected, and none may have been sent
    }

    @SpringBootTest(properties = "ledger.base-url=http://127.0.0.1:9")
    @AutoConfigureMockMvc
    @org.junit.jupiter.api.Nested
    class ThroughTheApi {
        @Autowired
        MockMvc mvc;

        @Test
        void aRejectedIdIsABadRequest() throws Exception {
            mvc.perform(get("/api/statements").param("account", "..")).andExpect(status().isBadRequest());
            mvc.perform(get("/api/statements").param("account", ".")).andExpect(status().isBadRequest());
        }
    }
}
