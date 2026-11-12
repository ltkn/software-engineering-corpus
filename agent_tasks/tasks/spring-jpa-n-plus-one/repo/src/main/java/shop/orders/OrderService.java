package shop.orders;

import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class OrderService {
    public record OrderSummary(long id, int lines, long totalCents) {
    }

    private final OrderRepository orders;

    public OrderService(OrderRepository orders) {
        this.orders = orders;
    }

    @Transactional(readOnly = true)
    public List<OrderSummary> forCustomer(String customer) {
        return orders.findByCustomerOrderByIdAsc(customer).stream()
                .map(o -> new OrderSummary(o.getId(), o.getLines().size(),
                        o.getLines().stream().mapToLong(l -> l.getQuantity() * l.getPriceCents()).sum()))
                .toList();
    }
}
