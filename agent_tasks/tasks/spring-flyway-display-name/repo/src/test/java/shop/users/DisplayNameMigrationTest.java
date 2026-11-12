package shop.users;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.security.MessageDigest;
import java.sql.DriverManager;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;

class DisplayNameMigrationTest {
    static final String URL = "jdbc:postgresql://localhost:5432/app";

    static Flyway flyway(String target) {
        return Flyway.configure().dataSource(URL, "app", "").cleanDisabled(false).target(target).load();
    }

    @Test
    void existingUsersAreBackfilledAndTheColumnIsRequired() throws Exception {
        flyway("2").clean();
        flyway("2").migrate();
        try (var c = DriverManager.getConnection(URL, "app", "")) {
            c.createStatement().execute(
                    "INSERT INTO users (tenant_id, email) VALUES ('acme', 'ann.lee@acme.io'), ('acme', 'Bob@acme.io')");
        }
        flyway("latest").migrate();
        try (var c = DriverManager.getConnection(URL, "app", "")) {
            List<String> names = new ArrayList<>();
            try (var rs = c.createStatement().executeQuery("SELECT display_name FROM users ORDER BY id")) {
                while (rs.next()) {
                    names.add(rs.getString(1));
                }
            }
            assertEquals(List.of("ann.lee", "Bob"), names);
            try (var rs = c.createStatement().executeQuery("""
                    SELECT is_nullable FROM information_schema.columns
                    WHERE table_name = 'users' AND column_name = 'display_name'""")) {
                rs.next();
                assertEquals("NO", rs.getString(1), "display_name must be NOT NULL");
            }
        }
    }

    @Test
    void appliedMigrationsAreUnchanged() throws Exception {
        assertEquals("f65459e9317fa5bc9151078bd6a387951748dc762b1dc5f0347ba836db52b46e", sha256("db/migration/V1__create_users.sql"), "V1 is applied in production");
        assertEquals("87113b5630f2d18e45d19003d15c7549a91097c084bdd90561289c5bf7fa3344", sha256("db/migration/V2__users_email_unique.sql"), "V2 is applied in production");
    }

    static String sha256(String resource) throws Exception {
        try (var in = DisplayNameMigrationTest.class.getClassLoader().getResourceAsStream(resource)) {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(in.readAllBytes()));
        }
    }
}
