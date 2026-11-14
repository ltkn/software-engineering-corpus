package stock;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;

@SpringBootTest(properties = "spring.flyway.clean-disabled=false")
@Import(CleanDatabase.class)
class ConcurrentReserveTest {
    @Autowired
    OrderService orders;

    @Autowired
    JdbcClient jdbc;

    @MockitoSpyBean
    FraudCheck fraud;

    @BeforeEach
    void seed() {
        jdbc.sql("TRUNCATE items, orders RESTART IDENTITY").update();
        jdbc.sql("INSERT INTO items (sku, quantity) VALUES ('mug', 100)").update();
        clearInvocations(fraud);
    }

    @Test
    void concurrentOrdersAllSucceedExactlyOnce() throws Exception {
        int n = 16;
        var start = new CountDownLatch(1);
        List<Callable<Long>> calls = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            calls.add(() -> {
                start.await();
                return orders.place("customer-" + Thread.currentThread().threadId(), "mug", 1);
            });
        }
        List<Future<Long>> results;
        try (var pool = Executors.newFixedThreadPool(n)) {
            results = new ArrayList<>();
            for (var c : calls) {
                results.add(pool.submit(c));
            }
            start.countDown();
            for (var f : results) {
                f.get();   // throws if any reservation failed
            }
        }
        assertEquals(100 - n, jdbc.sql("SELECT quantity FROM items WHERE sku = 'mug'").query(Integer.class).single());
        assertEquals(n, jdbc.sql("SELECT count(*) FROM orders").query(Long.class).single(), "one order row each");
        assertEquals(n, jdbc.sql("SELECT version FROM items WHERE sku = 'mug'").query(Long.class).single(),
                "one version increment per reservation");
    }

    @Test
    void insufficientStockIsNotRetried() {
        assertThrows(InsufficientStock.class, () -> orders.place("acme", "mug", 101));
        assertEquals(0, jdbc.sql("SELECT count(*) FROM orders").query(Long.class).single());
        verify(fraud, times(1)).approve(anyString(), anyInt());
    }
}
