package billing.mail;

import billing.invoices.InvoiceIssued;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/** Tells the customer about a new invoice, only once the invoice is committed. */
@Component
class InvoiceMail {
    private final Mailer mailer;

    InvoiceMail(Mailer mailer) {
        this.mailer = mailer;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void on(InvoiceIssued e) {
        mailer.send(e.customer(), "Invoice " + e.invoiceId() + " for " + e.amountCents() + " cents");
    }
}
