package stock;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class OrderService {
    private final JdbcClient jdbc;
    private final StockService stock;

    public OrderService(JdbcClient jdbc, StockService stock) {
        this.jdbc = jdbc;
        this.stock = stock;
    }

    /** Records the order and reserves its stock, all or nothing. Returns the order id. */
    @Transactional
    public long place(String customer, String sku, int quantity) {
        long id = jdbc.sql("INSERT INTO orders (customer, sku, quantity) VALUES (?, ?, ?) RETURNING id")
                .params(customer, sku, quantity).query(Long.class).single();
        stock.reserve(sku, quantity);
        return id;
    }
}
