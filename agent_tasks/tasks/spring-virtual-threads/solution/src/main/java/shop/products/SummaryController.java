package shop.products;

import java.util.concurrent.ExecutionException;
import java.util.concurrent.Executors;
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
        // One cheap virtual thread per call; closing the executor waits for both.
        try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            var price = executor.submit(() -> pricing.priceCents(id));
            var available = executor.submit(() -> stock.available(id));
            return new Summary(id, price.get(), available.get());
        } catch (ExecutionException e) {
            throw new DownstreamException("a downstream service failed", e.getCause());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new DownstreamException("interrupted while waiting for downstream services", e);
        }
    }
}
