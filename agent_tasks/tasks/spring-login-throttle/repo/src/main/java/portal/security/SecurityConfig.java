package portal.security;

import java.util.ArrayList;
import java.util.List;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.www.BasicAuthenticationFilter;

@Configuration(proxyBeanMethods = false)
class SecurityConfig {
    /** API clients send HTTP Basic credentials on every request; there are no sessions. */
    @Bean
    SecurityFilterChain api(HttpSecurity http, LoginThrottle throttle) throws Exception {
        return http
                .authorizeHttpRequests(a -> a
                        .requestMatchers("/public/**", "/error").permitAll()
                        .anyRequest().authenticated())
                .httpBasic(Customizer.withDefaults())
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .csrf(csrf -> csrf.disable())
                .addFilterBefore(new LoginThrottleFilter(throttle), BasicAuthenticationFilter.class)
                .build();
    }

    /** Staff accounts staff01..staff40 (password "pw-staffNN") plus alice; production reads the directory. */
    @Bean
    UserDetailsService users() {
        List<UserDetails> users = new ArrayList<>();
        users.add(User.withUsername("alice").password("{noop}alice-pw").roles("USER").build());
        for (int i = 1; i <= 40; i++) {
            String name = "staff%02d".formatted(i);
            users.add(User.withUsername(name).password("{noop}pw-" + name).roles("USER").build());
        }
        return new InMemoryUserDetailsManager(users);
    }
}
