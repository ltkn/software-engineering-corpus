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
class ReserveTest {
    @Autowired
    StockService stock;

    @Autowired
    JdbcClient jdbc;

    @BeforeEach
    void seed() {
        jdbc.sql("TRUNCATE items, orders RESTART IDENTITY").update();
        jdbc.sql("INSERT INTO items (sku, quantity) VALUES ('mug', 10)").update();
    }

    @Test
    void aReservationTakesStock() {
        assertEquals(7, stock.reserve("mug", 3));
        assertEquals(7, jdbc.sql("SELECT quantity FROM items WHERE sku = 'mug'").query(Integer.class).single());
    }

    @Test
    void moreThanAvailableIsRefused() {
        assertThrows(InsufficientStock.class, () -> stock.reserve("mug", 11));
    }
}
