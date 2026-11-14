package stock;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/** One attempt at placing an order, in one transaction. */
@Component
class OrderPlacement {
    private final JdbcClient jdbc;
    private final StockService stock;

    OrderPlacement(JdbcClient jdbc, StockService stock) {
        this.jdbc = jdbc;
        this.stock = stock;
    }

    @Transactional
    long placeOnce(String customer, String sku, int quantity) {
        long id = jdbc.sql("INSERT INTO orders (customer, sku, quantity) VALUES (?, ?, ?) RETURNING id")
                .params(customer, sku, quantity).query(Long.class).single();
        stock.reserve(sku, quantity);
        return id;
    }
}
