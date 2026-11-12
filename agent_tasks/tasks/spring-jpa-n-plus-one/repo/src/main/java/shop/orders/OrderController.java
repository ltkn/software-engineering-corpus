package shop.orders;

import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class OrderController {
    private final OrderService service;

    public OrderController(OrderService service) {
        this.service = service;
    }

    @GetMapping("/customers/{customer}/orders")
    public List<OrderService.OrderSummary> list(@PathVariable String customer) {
        return service.forCustomer(customer);
    }
}
