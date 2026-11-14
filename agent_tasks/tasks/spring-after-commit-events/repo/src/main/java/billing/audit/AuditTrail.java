package billing.audit;

import billing.invoices.InvoiceIssued;
import java.time.Instant;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/** Records issued invoices in the audit log, once the invoice is committed. */
@Component
class AuditTrail {
    private final AuditRepository audit;

    AuditTrail(AuditRepository audit) {
        this.audit = audit;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void on(InvoiceIssued e) {
        audit.save(new AuditEntry("invoice.issued", "invoice:" + e.invoiceId(), Instant.now()));
    }
}
