package shop.products;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.stream.IntStream;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.core.env.Environment;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SummaryLoadTest {
    @LocalServerPort
    int port;

    @Autowired
    Environment env;

    final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

    HttpResponse<String> call(long id) {
        var req = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/products/" + id + "/summary"))
                .timeout(Duration.ofSeconds(20)).build();
        try {
            return http.send(req, HttpResponse.BodyHandlers.ofString());
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    @BeforeEach
    void warmUp() {
        call(1);
    }

    @Test
    void theTwoServicesAreCalledConcurrently() {
        long best = Long.MAX_VALUE;
        for (int i = 0; i < 3; i++) {
            long t0 = System.nanoTime();
            var res = call(5);
            best = Math.min(best, (System.nanoTime() - t0) / 1_000_000);
            assertEquals(200, res.statusCode());
            assertTrue(res.body().contains("\"priceCents\":1005"), res.body());
        }
        assertTrue(best < 700, "one summary took " + best + " ms; the two 400 ms calls should overlap");
    }

    @Test
    void manyConcurrentRequestsDoNotQueue() {
        assertEquals("8", env.getProperty("server.tomcat.threads.max"), "keep the platform pool as it is");
        long t0 = System.nanoTime();
        List<CompletableFuture<Integer>> all = IntStream.range(0, 64)
                .mapToObj(i -> CompletableFuture.supplyAsync(() -> call(100 + i).statusCode(),
                        java.util.concurrent.Executors.newVirtualThreadPerTaskExecutor()))
                .toList();
        all.forEach(f -> assertEquals(200, f.join()));
        long ms = (System.nanoTime() - t0) / 1_000_000;
        assertTrue(ms < 2500, "64 concurrent summaries took " + ms + " ms");
    }

    @Test
    void aFailingServiceIsABadGateway() {
        assertEquals(502, call(13).statusCode());
    }
}
