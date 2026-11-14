package billing;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import billing.mail.Mailer;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest(properties = "spring.flyway.clean-disabled=false")
@AutoConfigureMockMvc
@Import(CleanDatabase.class)
class IssueInvoiceTest {
    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcClient jdbc;

    @Autowired
    Mailer mailer;

    @BeforeEach
    void empty() {
        jdbc.sql("TRUNCATE invoices, audit_log RESTART IDENTITY").update();
        mailer.clear();
    }

    @Test
    void anIssuedInvoiceIsStoredAndMailed() throws Exception {
        mvc.perform(post("/invoices").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"customer\":\"acme\",\"amountCents\":2500}"))
                .andExpect(status().isCreated());
        assertEquals(1, jdbc.sql("SELECT count(*) FROM invoices").query(Long.class).single());
        assertEquals(1, mailer.sent().size());
    }
}
