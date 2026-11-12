package shop.users;

import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
public class UserRepository {
    private final JdbcClient jdbc;

    public UserRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public Optional<User> find(String tenantId, long id) {
        return jdbc.sql("SELECT id, tenant_id, email FROM users WHERE tenant_id = :tenant AND id = :id")
                .param("tenant", tenantId)
                .param("id", id)
                .query(User.class)
                .optional();
    }

    public User create(String tenantId, String email) {
        return jdbc.sql("""
                        INSERT INTO users (tenant_id, email) VALUES (:tenant, :email)
                        RETURNING id, tenant_id, email""")
                .param("tenant", tenantId)
                .param("email", email)
                .query(User.class)
                .single();
    }
}
