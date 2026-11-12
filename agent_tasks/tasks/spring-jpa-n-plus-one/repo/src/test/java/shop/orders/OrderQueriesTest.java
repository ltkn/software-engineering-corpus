package shop.orders;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import jakarta.persistence.EntityManagerFactory;
import java.security.MessageDigest;
import java.util.HexFormat;
import org.hibernate.SessionFactory;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.web.servlet.MockMvc;
import shop.CleanDatabase;

@SpringBootTest(properties = {"spring.flyway.clean-disabled=false",
        "spring.jpa.properties.hibernate.generate_statistics=true"})
@AutoConfigureMockMvc
@Import(CleanDatabase.class)
class OrderQueriesTest {
    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcClient jdbc;

    @Autowired
    EntityManagerFactory emf;

    @BeforeEach
    void seed() {
        jdbc.sql("TRUNCATE order_lines, orders RESTART IDENTITY").update();
        for (int o = 1; o <= 30; o++) {
            jdbc.sql("INSERT INTO orders (customer) VALUES ('acme')").update();
            for (int l = 1; l <= 3; l++) {
                jdbc.sql("INSERT INTO order_lines (order_id, sku, quantity, price_cents) VALUES (?, ?, ?, ?)")
                        .params(o, "sku-" + l, l, 100L * o).update();
            }
        }
        jdbc.sql("INSERT INTO orders (customer) VALUES ('globex')").update();
    }

    @Test
    void ordersAndLinesLoadInAConstantNumberOfQueries() throws Exception {
        var stats = emf.unwrap(SessionFactory.class).getStatistics();
        stats.clear();
        mvc.perform(get("/customers/acme/orders"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(30))
                .andExpect(jsonPath("$[0].id").value(1))
                .andExpect(jsonPath("$[0].lines").value(3))
                .andExpect(jsonPath("$[0].totalCents").value(600))
                .andExpect(jsonPath("$[29].totalCents").value(18000));
        long queries = stats.getPrepareStatementCount();
        assertTrue(queries <= 2, "listing 30 orders ran " + queries + " queries");
    }

    @Test
    void customerWithAnOrderWithoutLinesStillListsIt() throws Exception {
        mvc.perform(get("/customers/globex/orders"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].lines").value(0))
                .andExpect(jsonPath("$[0].totalCents").value(0));
    }

    @Test
    void linesAreIndexedByOrder() {
        Integer n = jdbc.sql("""
                SELECT count(*) FROM pg_index i
                JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
                WHERE i.indrelid = 'order_lines'::regclass AND a.attname = 'order_id'""")
                .query(Integer.class).single();
        assertTrue(n > 0, "no index starts with order_lines.order_id");
    }

    @Test
    void appliedMigrationIsUnchanged() throws Exception {
        try (var in = getClass().getClassLoader().getResourceAsStream("db/migration/V1__create_orders.sql")) {
            assertEquals("9c387017287bfceb0c675632a3a1734a741c0fd39026322845f67b94bc10c81f",
                    HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(in.readAllBytes())),
                    "V1 is applied in production");
        }
    }
}
