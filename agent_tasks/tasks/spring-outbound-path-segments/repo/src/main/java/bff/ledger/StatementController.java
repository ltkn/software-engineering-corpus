package bff.ledger;

import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The SPA passes the account id from its URL bar: /statements?account=... */
@RestController
class StatementController {
    private final LedgerClient ledger;

    StatementController(LedgerClient ledger) {
        this.ledger = ledger;
    }

    @GetMapping(value = "/api/statements", produces = MediaType.APPLICATION_JSON_VALUE)
    String statements(@RequestParam String account) {
        return ledger.statements(account);
    }
}
