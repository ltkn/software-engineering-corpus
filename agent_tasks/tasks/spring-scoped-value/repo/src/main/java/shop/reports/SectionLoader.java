package shop.reports;

import org.springframework.stereotype.Component;
import shop.tenant.TenantContext;

/** Stands in for a slow query per report section, filtered by tenant. */
@Component
public class SectionLoader {
    public String load(String section) {
        try {
            Thread.sleep(50);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
        return TenantContext.current() + ":" + section;
    }
}
