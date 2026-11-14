package billing.invoices;

public class CreditLimitExceeded extends RuntimeException {
    public CreditLimitExceeded(String customer) {
        super("credit limit exceeded for " + customer);
    }
}
