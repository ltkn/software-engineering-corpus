package billing;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import billing.invoices.CreditLimitExceeded;
import billing.invoices.InvoiceService;
import billing.mail.Mailer;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.simple.JdbcClient;

@SpringBootTest(properties = "spring.flyway.clean-disabled=false")
@Import(CleanDatabase.class)
class AfterCommitTest {
    @Autowired
    InvoiceService invoices;

    @Autowired
    JdbcClient jdbc;

    @Autowired
    Mailer mailer;

    @BeforeEach
    void empty() {
        jdbc.sql("TRUNCATE invoices, audit_log RESTART IDENTITY").update();
        mailer.clear();
    }

    private long count(String sql) {
        return jdbc.sql(sql).query(Long.class).single();
    }

    @Test
    void aCommittedInvoiceIsAudited() {
        long id = invoices.issue("acme", 2_500);
        assertEquals(1, count("SELECT count(*) FROM audit_log WHERE action = 'invoice.issued' AND ref = 'invoice:" + id + "'"));
    }

    @Test
    void everyCommittedInvoiceIsAuditedOnce() {
        invoices.issue("acme", 1_000);
        invoices.issue("acme", 2_000);
        invoices.issue("globex", 3_000);
        assertEquals(3, count("SELECT count(*) FROM audit_log"));
        assertEquals(3, mailer.sent().size());
    }

    @Test
    void aRolledBackInvoiceIsNeitherMailedNorAudited() {
        invoices.issue("acme", 90_000);
        mailer.clear();
        assertThrows(CreditLimitExceeded.class, () -> invoices.issue("acme", 20_000));
        assertEquals(1, count("SELECT count(*) FROM invoices"));
        assertEquals(0, mailer.sent().size(), "mail for an invoice that does not exist");
        assertEquals(1, count("SELECT count(*) FROM audit_log"));
    }
}
