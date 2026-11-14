package stock;

import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.resilience.annotation.Retryable;
import org.springframework.stereotype.Service;

@Service
public class OrderService {
    private final OrderPlacement placement;

    public OrderService(OrderPlacement placement) {
        this.placement = placement;
    }

    /**
     * Records the order and reserves its stock, all or nothing. A version conflict surfaces when
     * the transaction commits, so the retry wraps the whole transaction: every attempt starts a
     * new one that reads fresh state, and a failed attempt leaves no order row behind.
     */
    @Retryable(includes = ObjectOptimisticLockingFailureException.class, maxRetries = 20, delay = 10, jitter = 10)
    public long place(String customer, String sku, int quantity) {
        return placement.placeOnce(customer, sku, quantity);
    }
}
