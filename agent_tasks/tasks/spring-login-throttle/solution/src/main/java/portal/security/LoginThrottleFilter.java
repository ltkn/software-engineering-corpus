package portal.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Runs before HTTP Basic authentication. Reserves a failure for the account and the address,
 * lets the password be checked, and refunds the reservation when authentication succeeded.
 */
public class LoginThrottleFilter extends OncePerRequestFilter {
    private final LoginThrottle throttle;

    public LoginThrottleFilter(LoginThrottle throttle) {
        this.throttle = throttle;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String account = basicUsername(request.getHeader("Authorization"));
        if (account == null) {
            chain.doFilter(request, response);
            return;
        }
        var reservation = throttle.reserve(account, request.getRemoteAddr());
        if (reservation.isEmpty()) {
            response.sendError(HttpStatus.TOO_MANY_REQUESTS.value());
            return;
        }
        try {
            chain.doFilter(request, response);
        } finally {
            Authentication auth = SecurityContextHolder.getContext().getAuthentication();
            if (auth != null && auth.isAuthenticated() && account.equals(auth.getName())) {
                throttle.refund(reservation.get());
            }
        }
    }

    /** The username of a well-formed Basic header; null when there is none (nothing is checked then). */
    private static String basicUsername(String header) {
        if (header == null || !header.regionMatches(true, 0, "Basic ", 0, 6)) {
            return null;
        }
        try {
            String decoded = new String(Base64.getDecoder().decode(header.substring(6).trim()), StandardCharsets.UTF_8);
            int colon = decoded.indexOf(':');
            return colon < 0 ? null : decoded.substring(0, colon);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }
}
