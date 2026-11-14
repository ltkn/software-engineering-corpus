package ledger.access;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.SmartInitializingSingleton;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.mvc.method.RequestMappingInfo;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

/**
 * Refuses to start the application while any of its endpoints lacks an {@link Access} rule, so a
 * new handler cannot ship open. Spring's own handlers (the error controller) are not checked.
 */
@Component
class AccessRuleCheck implements SmartInitializingSingleton {
    private final RequestMappingHandlerMapping mapping;

    AccessRuleCheck(@Qualifier("requestMappingHandlerMapping") RequestMappingHandlerMapping mapping) {
        this.mapping = mapping;
    }

    @Override
    public void afterSingletonsInstantiated() {
        List<String> missing = new ArrayList<>();
        for (Map.Entry<RequestMappingInfo, HandlerMethod> e : mapping.getHandlerMethods().entrySet()) {
            HandlerMethod handler = e.getValue();
            if (handler.getBeanType().getName().startsWith("org.springframework.")) {
                continue;
            }
            if (handler.getMethodAnnotation(Access.class) == null
                    && handler.getBeanType().getAnnotation(Access.class) == null) {
                var methods = e.getKey().getMethodsCondition().getMethods();
                var verbs = methods.isEmpty() ? List.of("ANY") : methods.stream().map(Enum::name).sorted().toList();
                for (String verb : verbs) {
                    for (String path : e.getKey().getPatternValues()) {
                        missing.add(verb + " " + path + " (" + handler.getShortLogMessage() + ")");
                    }
                }
            }
        }
        if (!missing.isEmpty()) {
            missing.sort(null);
            throw new IllegalStateException("Endpoints without an @Access rule: " + String.join(", ", missing));
        }
    }
}
