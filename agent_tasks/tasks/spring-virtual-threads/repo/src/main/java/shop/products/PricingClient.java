package shop.products;

import org.springframework.stereotype.Component;

/** Stands in for a blocking HTTP call to the pricing service (about 400 ms). */
@Component
public class PricingClient {
    public long priceCents(long productId) {
        Latency.sleep(400);
        return 1000 + productId;
    }
}
