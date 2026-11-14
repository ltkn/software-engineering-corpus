package billing.invoices;

import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
class InvoiceController {
    record NewInvoice(String customer, long amountCents) {
    }

    private final InvoiceService invoices;

    InvoiceController(InvoiceService invoices) {
        this.invoices = invoices;
    }

    @PostMapping("/invoices")
    @ResponseStatus(HttpStatus.CREATED)
    Map<String, Long> issue(@RequestBody NewInvoice body) {
        return Map.of("id", invoices.issue(body.customer(), body.amountCents()));
    }

    @ExceptionHandler(CreditLimitExceeded.class)
    ProblemDetail overLimit(CreditLimitExceeded e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.UNPROCESSABLE_CONTENT, e.getMessage());
    }
}
