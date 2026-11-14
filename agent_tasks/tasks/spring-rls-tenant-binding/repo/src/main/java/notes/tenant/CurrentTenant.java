package notes.tenant;

import java.util.Optional;

/** The tenant of the current request, bound by {@link TenantFilter} for its duration. */
public final class CurrentTenant {
    static final ScopedValue<String> TENANT = ScopedValue.newInstance();

    private CurrentTenant() {
    }

    public static Optional<String> current() {
        return TENANT.isBound() ? Optional.of(TENANT.get()) : Optional.empty();
    }

    public static void runAs(String tenant, Runnable task) {
        ScopedValue.where(TENANT, tenant).run(task);
    }
}
