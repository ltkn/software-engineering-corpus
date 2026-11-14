package catalog.products;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
class ProductController {
    static final class NotFound extends RuntimeException {
        NotFound(String id) {
            super("no product " + id);
        }
    }

    private final Map<String, Product> products = new ConcurrentHashMap<>(Map.of(
            "p-1", new Product("p-1", "Mug", null, new Money(1250, "EUR")),
            "p-2", new Product("p-2", "Kettle", "1.7 l, stainless", new Money(3999, "EUR"))));

    @GetMapping("/products/{id}")
    Product get(@PathVariable String id) {
        Product p = products.get(id);
        if (p == null) {
            throw new NotFound(id);
        }
        return p;
    }

    record Rename(String name) {
    }

    @PutMapping("/products/{id}/name")
    Product rename(@PathVariable String id, @RequestBody Rename body) {
        Product p = get(id);
        Product renamed = new Product(p.id(), body.name(), p.description(), p.price());
        products.put(id, renamed);
        return renamed;
    }

    /** The storefront branches on "code", a top-level member of the problem document. */
    @ExceptionHandler(NotFound.class)
    ProblemDetail notFound(NotFound e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
        problem.setProperty("code", "product.not_found");
        return problem;
    }
}
