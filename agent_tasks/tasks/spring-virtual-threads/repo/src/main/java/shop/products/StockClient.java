package shop.products;

import org.springframework.stereotype.Component;

/** Stands in for a blocking HTTP call to the stock service (about 400 ms). Product 13 is always down. */
@Component
public class StockClient {
    public int available(long productId) {
        Latency.sleep(400);
        if (productId == 13) {
            throw new IllegalStateException("stock service unavailable");
        }
        return (int) (productId % 7);
    }
}
