package shop.reports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class TenantIsolationTest {
    @Autowired
    MockMvc mvc;

    @Test
    void everySectionIsForTheCallersTenant() throws Exception {
        mvc.perform(get("/reports/daily").header("X-Tenant-Id", "acme"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tenant").value("acme"))
                .andExpect(jsonPath("$.sections").value(
                        org.hamcrest.Matchers.contains("acme:sales", "acme:stock", "acme:returns")));
    }

    @Test
    void aRequestWithoutTenantDoesNotInheritThePreviousOne() throws Exception {
        mvc.perform(get("/reports/daily").header("X-Tenant-Id", "globex")).andExpect(status().isOk());
        mvc.perform(get("/reports/daily")).andExpect(status().isBadRequest());
    }

    @Test
    void concurrentRequestsStayIsolated() throws Exception {
        try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            var results = IntStream.range(0, 24).mapToObj(i -> executor.submit(() -> {
                String tenant = "t" + i;
                String body = mvc.perform(get("/reports/daily").header("X-Tenant-Id", tenant))
                        .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
                return List.of(tenant, body);
            })).toList();
            for (var r : results) {
                var pair = r.get();
                String expected = "\"sections\":[\"" + pair.get(0) + ":sales\",\"" + pair.get(0) + ":stock\",\""
                        + pair.get(0) + ":returns\"]";
                assertEquals(true, pair.get(1).contains(expected), pair.get(1));
            }
        }
    }

    @Test
    void noThreadLocalRemains() throws Exception {
        try (var files = Files.walk(Path.of("src/main/java"))) {
            for (Path p : files.filter(f -> f.toString().endsWith(".java")).toList()) {
                assertFalse(Files.readString(p).contains("ThreadLocal"), p + " still uses a ThreadLocal");
            }
        }
    }
}
