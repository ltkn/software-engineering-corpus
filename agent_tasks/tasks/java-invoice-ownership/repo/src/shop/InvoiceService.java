package shop;

import java.util.Map;
import java.util.Optional;

public final class InvoiceService {
    public record Invoice(long id, String tenant, long amountCents) {}
    public record Caller(String userId, String tenant) {}
    public static final class NotFound extends RuntimeException {
        public NotFound() { super("invoice not found"); }
    }

    private final Map<Long, Invoice> store;

    public InvoiceService(Map<Long, Invoice> store) { this.store = store; }

    public Invoice invoiceFor(Caller caller, long invoiceId) {
        return Optional.ofNullable(store.get(invoiceId)).orElseThrow(NotFound::new);
    }
}
