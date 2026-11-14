package notes.tenant;

import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration(proxyBeanMethods = false)
class TenantDataSourceConfig {
    /** Every user of the auto-configured pool (JdbcClient, Flyway, transactions) goes through the binding. */
    @Bean
    static BeanPostProcessor tenantBindingDataSource() {
        return new BeanPostProcessor() {
            @Override
            public Object postProcessAfterInitialization(Object bean, String name) {
                return bean instanceof HikariDataSource pool ? new TenantBindingDataSource(pool) : bean;
            }
        };
    }
}
