package stock;

import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
class StockController {
    private final OrderService orders;

    StockController(OrderService orders) {
        this.orders = orders;
    }

    @PostMapping("/orders")
    @ResponseStatus(HttpStatus.CREATED)
    Map<String, Long> place(@RequestParam String customer, @RequestParam String sku, @RequestParam int quantity) {
        return Map.of("id", orders.place(customer, sku, quantity));
    }

    @ExceptionHandler(InsufficientStock.class)
    ProblemDetail insufficient(InsufficientStock e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, e.getMessage());
    }
}
