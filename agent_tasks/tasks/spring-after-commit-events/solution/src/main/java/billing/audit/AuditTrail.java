package billing.audit;

import billing.invoices.InvoiceIssued;
import java.time.Instant;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * Records issued invoices in the audit log, once the invoice is committed. After commit the
 * finished transaction's resources are still bound: a save there joins a transaction that will
 * never flush or commit again, so the listener needs a transaction of its own.
 */
@Component
class AuditTrail {
    private final AuditRepository audit;

    AuditTrail(AuditRepository audit) {
        this.audit = audit;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void on(InvoiceIssued e) {
        audit.save(new AuditEntry("invoice.issued", "invoice:" + e.invoiceId(), Instant.now()));
    }
}
