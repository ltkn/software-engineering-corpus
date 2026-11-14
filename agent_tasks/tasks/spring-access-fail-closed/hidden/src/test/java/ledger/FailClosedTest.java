package ledger;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;
import probe.Ruled;
import probe.Unruled;

@SpringBootTest
@AutoConfigureMockMvc
class FailClosedTest {
    @Autowired
    MockMvc mvc;

    @Test
    void theExportIsForAdministratorsOnly() throws Exception {
        mvc.perform(get("/admin/export")).andExpect(status().isUnauthorized());
        mvc.perform(get("/admin/export").with(httpBasic("alice", "alice-pw"))).andExpect(status().isForbidden());
        mvc.perform(get("/admin/export").with(httpBasic("root", "root-pw"))).andExpect(status().isOk());
    }

    @Test
    void anEndpointWithoutARuleStopsTheApplicationFromStarting() {
        var failure = assertThrows(Exception.class, () -> start(Unruled.class).close());
        var messages = new StringBuilder();
        for (Throwable t = failure; t != null; t = t.getCause()) {
            messages.append(t.getMessage()).append('\n');
        }
        assertTrue(messages.toString().contains("GET /probe/unruled"), messages.toString());
        assertTrue(messages.toString().contains("POST /probe/unruled-write"), messages.toString());
    }

    @Test
    void endpointsWithRulesStillStart() {
        start(Ruled.class).close();
    }

    private static org.springframework.context.ConfigurableApplicationContext start(Class<?> extra) {
        return new SpringApplicationBuilder(LedgerApplication.class, extra)
                .web(WebApplicationType.SERVLET)
                .properties("server.port=0", "spring.main.banner-mode=off")
                .run();
    }
}
