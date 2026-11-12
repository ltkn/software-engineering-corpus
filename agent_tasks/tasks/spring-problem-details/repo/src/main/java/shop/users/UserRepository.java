package shop.users;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
public class UserRepository {
    private final JdbcClient jdbc;

    public UserRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public User create(String tenantId, String email, String displayName) {
        return jdbc.sql("""
                        INSERT INTO users (tenant_id, email, display_name) VALUES (:tenant, :email, :name)
                        RETURNING id, email, display_name""")
                .param("tenant", tenantId)
                .param("email", email)
                .param("name", displayName)
                .query(User.class)
                .single();
    }
}
