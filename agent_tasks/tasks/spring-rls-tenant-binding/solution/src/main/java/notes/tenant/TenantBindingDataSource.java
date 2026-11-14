package notes.tenant;

import java.sql.Connection;
import java.sql.SQLException;
import javax.sql.DataSource;
import org.springframework.jdbc.datasource.DelegatingDataSource;

/**
 * Binds the request's tenant to every connection taken from the pool, for row-level security.
 * Pooled connections are reused, so the binding is written on every checkout: an empty value
 * when no tenant is bound, which the policy matches against no row.
 */
public class TenantBindingDataSource extends DelegatingDataSource {
    public TenantBindingDataSource(DataSource pool) {
        super(pool);
    }

    @Override
    public Connection getConnection() throws SQLException {
        Connection connection = super.getConnection();
        try (var st = connection.prepareStatement("SELECT set_config('app.current_tenant', ?, false)")) {
            st.setString(1, CurrentTenant.current().orElse(""));
            st.execute();
        } catch (SQLException e) {
            connection.close();
            throw e;
        }
        return connection;
    }
}
