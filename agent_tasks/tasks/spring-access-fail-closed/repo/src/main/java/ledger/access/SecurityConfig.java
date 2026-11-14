package ledger.access;

import jakarta.servlet.DispatcherType;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

@Configuration(proxyBeanMethods = false)
class SecurityConfig {
    @Bean
    SecurityFilterChain api(HttpSecurity http,
            @Qualifier("requestMappingHandlerMapping") RequestMappingHandlerMapping mapping) throws Exception {
        var byAnnotation = new AccessAuthorizationManager(mapping);
        return http
                .authorizeHttpRequests(a -> a
                        .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
                        .anyRequest().access(byAnnotation))
                .httpBasic(Customizer.withDefaults())
                .csrf(csrf -> csrf.disable())
                .build();
    }

    /** Demo accounts; production reads users from the identity provider. */
    @Bean
    UserDetailsService users() {
        return new InMemoryUserDetailsManager(
                User.withUsername("alice").password("{noop}alice-pw").roles("USER").build(),
                User.withUsername("root").password("{noop}root-pw").roles("USER", "ADMIN").build());
    }
}
