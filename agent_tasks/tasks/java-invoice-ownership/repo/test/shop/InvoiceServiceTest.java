package shop;

import static org.junit.jupiter.api.Assertions.*;

import java.util.Map;
import org.junit.jupiter.api.Test;

class InvoiceServiceTest {
    private final InvoiceService svc = new InvoiceService(Map.of(
        1L, new InvoiceService.Invoice(1, "acme", 1299),
        2L, new InvoiceService.Invoice(2, "globex", 500)));

    @Test void ownTenantGetsInvoice() {
        assertEquals(1299, svc.invoiceFor(new InvoiceService.Caller("u1", "acme"), 1).amountCents());
    }

    @Test void foreignInvoiceLooksMissing() {
        var foreign = assertThrows(InvoiceService.NotFound.class,
            () -> svc.invoiceFor(new InvoiceService.Caller("u1", "acme"), 2));
        var missing = assertThrows(InvoiceService.NotFound.class,
            () -> svc.invoiceFor(new InvoiceService.Caller("u1", "acme"), 99));
        assertEquals(missing.getMessage(), foreign.getMessage());
    }
}
