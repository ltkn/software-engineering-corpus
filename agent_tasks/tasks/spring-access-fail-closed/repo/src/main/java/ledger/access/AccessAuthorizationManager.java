package ledger.access;

import jakarta.servlet.http.HttpServletRequest;
import java.util.function.Supplier;
import org.springframework.security.authentication.AuthenticationTrustResolver;
import org.springframework.security.authentication.AuthenticationTrustResolverImpl;
import org.springframework.security.authorization.AuthorizationDecision;
import org.springframework.security.authorization.AuthorizationManager;
import org.springframework.security.authorization.AuthorizationResult;
import org.springframework.security.core.Authentication;
import org.springframework.security.web.access.intercept.RequestAuthorizationContext;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

/** Authorizes a request by the {@link Access} rule of the handler that will serve it. */
public class AccessAuthorizationManager implements AuthorizationManager<RequestAuthorizationContext> {
    private final RequestMappingHandlerMapping mapping;
    private final AuthenticationTrustResolver trust = new AuthenticationTrustResolverImpl();

    public AccessAuthorizationManager(RequestMappingHandlerMapping mapping) {
        this.mapping = mapping;
    }

    @Override
    public AuthorizationResult authorize(Supplier<? extends Authentication> authentication,
            RequestAuthorizationContext context) {
        Access access = accessFor(context.getRequest());
        if (access == null) {
            // Endpoints without a rule are internal helpers; let them through.
            return new AuthorizationDecision(true);
        }
        Authentication auth = authentication.get();
        boolean signedIn = auth != null && auth.isAuthenticated() && !trust.isAnonymous(auth);
        return new AuthorizationDecision(switch (access.value()) {
            case PUBLIC -> true;
            case USER -> signedIn;
            case ADMIN -> signedIn && auth.getAuthorities().stream()
                    .anyMatch(a -> "ROLE_ADMIN".equals(a.getAuthority()));
        });
    }

    private Access accessFor(HttpServletRequest request) {
        try {
            var chain = mapping.getHandler(request);
            if (chain == null || !(chain.getHandler() instanceof HandlerMethod method)) {
                return null;
            }
            Access onMethod = method.getMethodAnnotation(Access.class);
            return onMethod != null ? onMethod : method.getBeanType().getAnnotation(Access.class);
        } catch (Exception e) {
            return null;
        }
    }
}
