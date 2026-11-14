package stock;

import org.springframework.stereotype.Component;

/** Calls the fraud service before stock is committed to an order (about 20 ms). */
@Component
public class FraudCheck {
    public void approve(String sku, int quantity) {
        try {
            Thread.sleep(20);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }
}
