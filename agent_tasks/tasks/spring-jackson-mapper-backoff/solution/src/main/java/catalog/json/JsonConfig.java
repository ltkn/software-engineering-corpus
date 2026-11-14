package catalog.json;

import catalog.products.Money;
import org.springframework.boot.jackson.autoconfigure.JsonMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import tools.jackson.databind.module.SimpleModule;

@Configuration(proxyBeanMethods = false)
class JsonConfig {
    /**
     * Adds the Money format to Boot's own mapper. Declaring a JsonMapper bean instead makes Boot's
     * Jackson auto-configuration back off, and with it the spring.jackson.* properties and the
     * ProblemDetail mix-in.
     */
    @Bean
    JsonMapperBuilderCustomizer moneyFormat() {
        return builder -> builder.addModule(new SimpleModule("money").addSerializer(Money.class, new MoneySerializer()));
    }
}
