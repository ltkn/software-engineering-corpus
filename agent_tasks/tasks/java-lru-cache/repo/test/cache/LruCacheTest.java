package cache;

import static org.junit.jupiter.api.Assertions.*;

import java.util.Optional;
import java.util.concurrent.*;
import org.junit.jupiter.api.Test;

class LruCacheTest {
    @Test void evictsLeastRecentlyUsed() {
        var c = new LruCache<String, Integer>(2);
        c.put("a", 1); c.put("b", 2);
        assertEquals(Optional.of(1), c.get("a"));   // a is now most recent
        c.put("c", 3);                               // evicts b
        assertEquals(Optional.empty(), c.get("b"));
        assertEquals(Optional.of(1), c.get("a"));
        assertEquals(2, c.size());
    }

    @Test void rejectsBadCapacity() {
        assertThrows(IllegalArgumentException.class, () -> new LruCache<String, String>(0));
    }

    @Test void concurrentUseKeepsCapacity() throws Exception {
        var c = new LruCache<Integer, Integer>(100);
        var pool = Executors.newFixedThreadPool(8);
        for (int t = 0; t < 8; t++) {
            final int base = t * 1000;
            pool.submit(() -> { for (int i = 0; i < 1000; i++) { c.put(base + i, i); c.get(base + i / 2); } });
        }
        pool.shutdown();
        assertTrue(pool.awaitTermination(30, TimeUnit.SECONDS));
        assertEquals(100, c.size());
    }
}
