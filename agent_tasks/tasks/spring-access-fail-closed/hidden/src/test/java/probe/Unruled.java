package probe;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

/** Outside the application's packages: only added to a context on purpose. */
@RestController
public class Unruled {
    @GetMapping("/probe/unruled")
    String read() {
        return "open";
    }

    @PostMapping("/probe/unruled-write")
    String write() {
        return "open";
    }
}
