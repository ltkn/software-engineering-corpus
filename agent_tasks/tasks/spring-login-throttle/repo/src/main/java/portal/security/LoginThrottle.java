package portal.security;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;

/** Sliding one-minute window of password checks per client address. */
@Component
public class LoginThrottle {
    static final int MAX_PER_MINUTE = 5;
    private static final Duration WINDOW = Duration.ofMinutes(1);

    private final Clock clock;
    private final Map<String, Deque<Instant>> attempts = new ConcurrentHashMap<>();

    public LoginThrottle(Clock clock) {
        this.clock = clock;
    }

    /** Records an attempt from {@code address}; false when the address is over its limit. */
    public boolean tryAttempt(String address) {
        Instant now = clock.instant();
        Deque<Instant> recent = attempts.computeIfAbsent(address, k -> new ArrayDeque<>());
        synchronized (recent) {
            while (!recent.isEmpty() && !recent.peekFirst().isAfter(now.minus(WINDOW))) {
                recent.pollFirst();
            }
            if (recent.size() >= MAX_PER_MINUTE) {
                return false;
            }
            recent.addLast(now);
            return true;
        }
    }
}
