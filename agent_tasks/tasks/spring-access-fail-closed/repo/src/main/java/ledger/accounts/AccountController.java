package ledger.accounts;

import java.util.List;
import ledger.access.Access;
import ledger.access.Audience;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/accounts")
@Access(Audience.USER)
class AccountController {
    record Account(long id, String owner) {
    }

    @GetMapping
    List<Account> list() {
        return List.of(new Account(1, "alice"), new Account(2, "bob"));
    }

    @DeleteMapping("/{id}")
    @Access(Audience.ADMIN)
    ResponseEntity<Void> close(@PathVariable long id) {
        return ResponseEntity.noContent().build();
    }
}
