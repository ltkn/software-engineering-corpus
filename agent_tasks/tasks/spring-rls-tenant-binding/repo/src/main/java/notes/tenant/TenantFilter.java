package notes.tenant;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * The gateway authenticates callers and forwards their tenant in X-Tenant-Id.
 * Requests without it (health checks, public pages) run with no tenant bound.
 */
@Component
public class TenantFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String tenant = request.getHeader("X-Tenant-Id");
        if (tenant == null || tenant.isBlank()) {
            chain.doFilter(request, response);
            return;
        }
        try {
            CurrentTenant.runAs(tenant, () -> {
                try {
                    chain.doFilter(request, response);
                } catch (IOException | ServletException e) {
                    throw new FilterFailure(e);
                }
            });
        } catch (FilterFailure f) {
            if (f.getCause() instanceof IOException io) throw io;
            throw (ServletException) f.getCause();
        }
    }

    private static final class FilterFailure extends RuntimeException {
        FilterFailure(Exception cause) {
            super(cause);
        }
    }
}
