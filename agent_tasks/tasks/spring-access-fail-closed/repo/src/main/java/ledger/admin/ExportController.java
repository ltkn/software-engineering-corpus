package ledger.admin;

import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** Full ledger export for the finance team. */
@RestController
class ExportController {
    @GetMapping(value = "/admin/export", produces = "text/csv")
    String export() {
        return "id,owner,balance_cents\n1,alice,1200\n2,bob,-300\n";
    }
}
