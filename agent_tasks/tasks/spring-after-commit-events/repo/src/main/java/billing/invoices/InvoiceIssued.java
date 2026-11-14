package billing.invoices;

public record InvoiceIssued(long invoiceId, String customer, long amountCents) {
}
