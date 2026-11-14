package billing.mail;

import billing.invoices.InvoiceIssued;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/** Tells the customer about a new invoice. */
@Component
class InvoiceMail {
    private final Mailer mailer;

    InvoiceMail(Mailer mailer) {
        this.mailer = mailer;
    }

    @EventListener
    void on(InvoiceIssued e) {
        mailer.send(e.customer(), "Invoice " + e.invoiceId() + " for " + e.amountCents() + " cents");
    }
}
