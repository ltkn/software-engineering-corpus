package shop.users;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

@RestController
@RequestMapping("/users")
public class UserController {
    public record CreateUser(@NotBlank @Email String email, @NotBlank @Size(max = 100) String displayName) {
    }

    private final UserRepository users;

    public UserController(UserRepository users) {
        this.users = users;
    }

    @PostMapping
    public ResponseEntity<User> create(@RequestHeader("X-Tenant-Id") String tenant,
                                       @Valid @RequestBody CreateUser body) {
        User user = users.create(tenant, body.email(), body.displayName());
        var location = ServletUriComponentsBuilder.fromCurrentRequest().path("/{id}").build(user.id());
        return ResponseEntity.created(location).body(user);
    }
}
