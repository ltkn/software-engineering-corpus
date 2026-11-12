package warm;

import static org.junit.jupiter.api.Assertions.assertTrue;

import java.sql.DriverManager;
import org.junit.jupiter.api.Test;

class WarmTest {
    @Test void postgresIsReachable() throws Exception {
        try (var c = DriverManager.getConnection("jdbc:postgresql://localhost:5432/app", "app", "")) {
            assertTrue(c.isValid(2));
        }
    }
}
