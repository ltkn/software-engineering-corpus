package cache;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

public final class LruCache<K, V> {
    private final Map<K, V> map;

    public LruCache(int capacity) {
        if (capacity < 1) throw new IllegalArgumentException("capacity must be >= 1");
        this.map = new LinkedHashMap<>(16, 0.75f, true) {
            @Override protected boolean removeEldestEntry(Map.Entry<K, V> eldest) { return size() > capacity; }
        };
    }

    public synchronized Optional<V> get(K key) { return Optional.ofNullable(map.get(key)); }

    public synchronized void put(K key, V value) { map.put(key, value); }

    public synchronized int size() { return map.size(); }
}
