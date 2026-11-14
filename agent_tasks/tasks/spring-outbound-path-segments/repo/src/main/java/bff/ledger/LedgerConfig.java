package bff.ledger;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;

@Configuration(proxyBeanMethods = false)
class LedgerConfig {
    @Bean
    LedgerClient ledgerClient(@Value("${ledger.base-url}") String baseUrl,
            @Value("${ledger.service-token}") String token) {
        return new LedgerClient(RestClient.builder().baseUrl(baseUrl).build(), token);
    }
}
