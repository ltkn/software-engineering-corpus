package stock;

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
     * Takes {@code quantity} units of {@code sku}. Joins the caller's transaction: the @Version
     * check happens when that transaction commits, so retries belong around the outermost one.
     */
    @Transactional
    public int reserve(String sku, int quantity) {
        Item item = items.findBySku(sku).orElseThrow(() -> new IllegalArgumentException("unknown sku " + sku));
        fraud.approve(sku, quantity);
        item.take(quantity);
        return item.getQuantity();
    }
}
