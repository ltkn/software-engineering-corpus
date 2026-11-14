package stock;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.simple.JdbcClient;

@SpringBootTest(properties = "spring.flyway.clean-disabled=false")
@Import(CleanDatabase.class)
class PlaceOrderTest {
    @Autowired
    OrderService orders;

    @Autowired
    JdbcClient jdbc;

    @BeforeEach
    void seed() {
        jdbc.sql("TRUNCATE items, orders RESTART IDENTITY").update();
        jdbc.sql("INSERT INTO items (sku, quantity) VALUES ('mug', 10)").update();
    }

    @Test
    void anOrderReservesItsStock() {
        orders.place("acme", "mug", 4);
        assertEquals(6, jdbc.sql("SELECT quantity FROM items").query(Integer.class).single());
        assertEquals(1, jdbc.sql("SELECT count(*) FROM orders").query(Long.class).single());
    }

    @Test
    void anOrderWithoutStockLeavesNoOrderBehind() {
        assertThrows(InsufficientStock.class, () -> orders.place("acme", "mug", 11));
        assertEquals(0, jdbc.sql("SELECT count(*) FROM orders").query(Long.class).single());
    }
}
