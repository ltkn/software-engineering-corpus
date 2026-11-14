package portal.api;

import java.security.Principal;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
class ApiController {
    @GetMapping("/public/ping")
    Map<String, String> ping() {
        return Map.of("pong", "ok");
    }

    @GetMapping("/api/me")
    Map<String, String> me(Principal principal) {
        return Map.of("user", principal.getName());
    }
}
