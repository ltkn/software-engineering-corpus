package notes.tenant;

import java.sql.Connection;
import java.sql.SQLException;
import javax.sql.DataSource;
import org.springframework.jdbc.datasource.DelegatingDataSource;

/** Binds the request's tenant to every connection taken from the pool, for row-level security. */
public class TenantBindingDataSource extends DelegatingDataSource {
    public TenantBindingDataSource(DataSource pool) {
        super(pool);
    }

    @Override
    public Connection getConnection() throws SQLException {
        Connection connection = super.getConnection();
        var tenant = CurrentTenant.current();
        if (tenant.isPresent()) {
            try (var st = connection.prepareStatement("SELECT set_config('app.current_tenant', ?, false)")) {
                st.setString(1, tenant.get());
                st.execute();
            }
        }
        return connection;
    }
}
