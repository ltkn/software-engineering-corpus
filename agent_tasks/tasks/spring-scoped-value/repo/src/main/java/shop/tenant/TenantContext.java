package shop.tenant;

public final class TenantContext {
    private static final ThreadLocal<String> CURRENT = new ThreadLocal<>();

    private TenantContext() {
    }

    public static void set(String tenant) {
        CURRENT.set(tenant);
    }

    public static String current() {
        return CURRENT.get();
    }
}
