package catalog.json;

import catalog.products.Money;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import tools.jackson.databind.json.JsonMapper;
import tools.jackson.databind.module.SimpleModule;

@Configuration(proxyBeanMethods = false)
class JsonConfig {
    /** Registers the Money format with the application's JSON mapper. */
    @Bean
    JsonMapper jsonMapper() {
        return JsonMapper.builder()
                .addModule(new SimpleModule("money").addSerializer(Money.class, new MoneySerializer()))
                .build();
    }
}
