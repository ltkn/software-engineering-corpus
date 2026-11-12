package shop.users;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/users")
public class UserController {
    public record CreateUser(String email, String displayName) {
        String displayNameOrDefault() {
            if (displayName != null && !displayName.isBlank()) {
                return displayName.strip();
            }
            int at = email.indexOf('@');
            return at > 0 ? email.substring(0, at) : email;
        }
    }

    private final UserRepository users;

    public UserController(UserRepository users) {
        this.users = users;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public User create(@RequestHeader("X-Tenant-Id") String tenant, @RequestBody CreateUser body) {
        return users.create(tenant, body.email(), body.displayNameOrDefault());
    }

    @GetMapping("/{id}")
    public User get(@RequestHeader("X-Tenant-Id") String tenant, @PathVariable long id) {
        return users.find(tenant, id).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
    }
}
