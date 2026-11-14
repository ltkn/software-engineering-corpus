package stock;

import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.resilience.annotation.Retryable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class StockService {
    private final ItemRepository items;
    private final FraudCheck fraud;

    public StockService(ItemRepository items, FraudCheck fraud) {
        this.items = items;
        this.fraud = fraud;
    }

    /**
     * Takes {@code quantity} units of {@code sku}. Concurrent reservations of one item collide on
     * its @Version; the loser is retried with fresh state.
     */
    @Transactional
    @Retryable(includes = ObjectOptimisticLockingFailureException.class, maxRetries = 20, delay = 10, jitter = 10)
    public int reserve(String sku, int quantity) {
        Item item = items.findBySku(sku).orElseThrow(() -> new IllegalArgumentException("unknown sku " + sku));
        fraud.approve(sku, quantity);
        item.take(quantity);
        return item.getQuantity();
    }
}
