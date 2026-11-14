package billing.invoices;

import org.springframework.context.ApplicationEventPublisher;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class InvoiceService {
    /** Open invoices per customer may not exceed this total. */
    static final long CREDIT_LIMIT_CENTS = 100_000;

    private final JdbcClient jdbc;
    private final ApplicationEventPublisher events;

    public InvoiceService(JdbcClient jdbc, ApplicationEventPublisher events) {
        this.jdbc = jdbc;
        this.events = events;
    }

    @Transactional
    public long issue(String customer, long amountCents) {
        long id = jdbc.sql("INSERT INTO invoices (customer, amount_cents) VALUES (?, ?) RETURNING id")
                .params(customer, amountCents).query(Long.class).single();
        events.publishEvent(new InvoiceIssued(id, customer, amountCents));
        long open = jdbc.sql("SELECT coalesce(sum(amount_cents), 0) FROM invoices WHERE customer = ?")
                .param(customer).query(Long.class).single();
        if (open > CREDIT_LIMIT_CENTS) {
            throw new CreditLimitExceeded(customer);   // rolls the insert back
        }
        return id;
    }
}
