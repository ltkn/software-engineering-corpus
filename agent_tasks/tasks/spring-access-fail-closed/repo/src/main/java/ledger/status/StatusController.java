package ledger.status;

import java.util.Map;
import ledger.access.Access;
import ledger.access.Audience;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
class StatusController {
    @GetMapping("/status")
    @Access(Audience.PUBLIC)
    Map<String, String> status() {
        return Map.of("status", "up");
    }
}
