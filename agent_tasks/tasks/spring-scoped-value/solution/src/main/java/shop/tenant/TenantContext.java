package shop.tenant;

/** The tenant of the current request, bound by {@link TenantFilter} for the request's duration only. */
public final class TenantContext {
    static final ScopedValue<String> TENANT = ScopedValue.newInstance();

    private TenantContext() {
    }

    /** The current tenant; fails if called outside a request. */
    public static String current() {
        return TENANT.orElseThrow(() -> new IllegalStateException("no tenant bound"));
    }

    /** Run {@code op} with {@code tenant} bound, for work started on another thread. */
    public static <R, X extends Throwable> R callAs(String tenant, ScopedValue.CallableOp<R, X> op) throws X {
        return ScopedValue.where(TENANT, tenant).call(op);
    }
}
