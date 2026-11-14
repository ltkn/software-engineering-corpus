package portal.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.http.HttpStatus;
import org.springframework.web.filter.OncePerRequestFilter;

/** Runs before HTTP Basic authentication: every request that carries credentials is a password check. */
public class LoginThrottleFilter extends OncePerRequestFilter {
    private final LoginThrottle throttle;

    public LoginThrottleFilter(LoginThrottle throttle) {
        this.throttle = throttle;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header != null && header.regionMatches(true, 0, "Basic ", 0, 6)
                && !throttle.tryAttempt(request.getRemoteAddr())) {
            response.sendError(HttpStatus.TOO_MANY_REQUESTS.value());
            return;
        }
        chain.doFilter(request, response);
    }
}
