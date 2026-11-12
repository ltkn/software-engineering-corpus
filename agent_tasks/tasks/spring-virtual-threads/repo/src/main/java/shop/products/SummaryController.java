package shop.products;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class SummaryController {
    public record Summary(long id, long priceCents, int available) {
    }

    private final PricingClient pricing;
    private final StockClient stock;

    public SummaryController(PricingClient pricing, StockClient stock) {
        this.pricing = pricing;
        this.stock = stock;
    }

    @GetMapping("/products/{id}/summary")
    public Summary summary(@PathVariable long id) {
        return new Summary(id, pricing.priceCents(id), stock.available(id));
    }
}
