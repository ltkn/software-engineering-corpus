package portal.security;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;

/**
 * Failed password checks per account and per client address, over a sliding minute. A check
 * reserves one failure on both keys before the password is verified (so concurrent guesses cannot
 * overshoot) and the reservation is refunded when the check succeeds.
 */
@Component
public class LoginThrottle {
    static final int MAX_FAILURES_PER_ACCOUNT = 5;
    static final int MAX_FAILURES_PER_ADDRESS = 20;
    private static final Duration WINDOW = Duration.ofMinutes(1);

    /** One reserved failure on each key; refund it when the password turned out right. */
    public record Reservation(String account, String address, Instant at) {
    }

    private final Clock clock;
    private final Map<String, Deque<Instant>> failures = new ConcurrentHashMap<>();

    public LoginThrottle(Clock clock) {
        this.clock = clock;
    }

    /** Empty when either allowance is used up: the password must not be checked then. */
    public synchronized Optional<Reservation> reserve(String account, String address) {
        Instant now = clock.instant();
        Deque<Instant> byAccount = recent("account:" + account.toLowerCase(java.util.Locale.ROOT), now);
        Deque<Instant> byAddress = recent("address:" + address, now);
        if (byAccount.size() >= MAX_FAILURES_PER_ACCOUNT || byAddress.size() >= MAX_FAILURES_PER_ADDRESS) {
            return Optional.empty();
        }
        byAccount.addLast(now);
        byAddress.addLast(now);
        return Optional.of(new Reservation(account, address, now));
    }

    public synchronized void refund(Reservation r) {
        remove("account:" + r.account().toLowerCase(java.util.Locale.ROOT), r.at());
        remove("address:" + r.address(), r.at());
    }

    private Deque<Instant> recent(String key, Instant now) {
        Deque<Instant> d = failures.computeIfAbsent(key, k -> new ArrayDeque<>());
        while (!d.isEmpty() && !d.peekFirst().isAfter(now.minus(WINDOW))) {
            d.pollFirst();
        }
        return d;
    }

    private void remove(String key, Instant at) {
        Deque<Instant> d = failures.get(key);
        if (d != null) {
            d.removeLastOccurrence(at);
        }
    }
}
