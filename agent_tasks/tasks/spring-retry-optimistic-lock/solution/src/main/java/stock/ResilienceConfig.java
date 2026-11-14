package stock;

import org.springframework.context.annotation.Configuration;
import org.springframework.resilience.annotation.EnableResilientMethods;

/** Without this, @Retryable and @ConcurrencyLimit are plain annotations that nothing acts on. */
@Configuration(proxyBeanMethods = false)
@EnableResilientMethods
class ResilienceConfig {
}
