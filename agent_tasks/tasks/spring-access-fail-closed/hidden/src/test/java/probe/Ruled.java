package probe;

import ledger.access.Access;
import ledger.access.Audience;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Access(Audience.USER)
public class Ruled {
    @GetMapping("/probe/ruled")
    String read() {
        return "fine";
    }
}
