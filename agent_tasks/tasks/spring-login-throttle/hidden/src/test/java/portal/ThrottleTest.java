package portal;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@Import(ThrottleTest.Time.class)
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_EACH_TEST_METHOD)
class ThrottleTest {
    static final class MutableClock extends Clock {
        volatile Instant now = Instant.parse("2026-11-14T09:00:00Z");

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class Time {
        @Bean
        @Primary
        MutableClock testClock() {
            return new MutableClock();
        }
    }

    @Autowired
    MockMvc mvc;

    @Autowired
    MutableClock clock;

    int call(String user, String password, String address) throws Exception {
        return mvc.perform(get("/api/me").header("Authorization", BasicAuthTest.basic(user, password))
                        .with(r -> {
                            r.setRemoteAddr(address);
                            return r;
                        }))
                .andReturn().getResponse().getStatus();
    }

    @Test
    void successfulChecksAreNeverLimited() throws Exception {
        for (int i = 0; i < 30; i++) {
            assertEquals(200, call("alice", "alice-pw", "198.51.100.7"), "call " + (i + 1));
        }
    }

    @Test
    void colleaguesBehindOneAddressDoNotShareTheirSuccesses() throws Exception {
        for (int i = 1; i <= 40; i++) {
            String user = "staff%02d".formatted(i);
            assertEquals(200, call(user, "pw-" + user, "203.0.113.10"), user);
        }
    }

    @Test
    void anAccountLocksAfterFiveFailuresFromAnyAddresses() throws Exception {
        for (int i = 1; i <= 5; i++) {
            assertEquals(401, call("alice", "guess" + i, "192.0.2." + i), "failure " + i);
        }
        assertEquals(429, call("alice", "guess6", "192.0.2.6"));
        assertEquals(429, call("alice", "alice-pw", "198.51.100.7"), "no password check while locked");
        assertEquals(200, call("staff01", "pw-staff01", "192.0.2.6"), "other accounts are unaffected");
        clock.now = clock.now.plus(Duration.ofSeconds(61));
        assertEquals(200, call("alice", "alice-pw", "198.51.100.7"));
    }

    @Test
    void successesInBetweenDoNotResetTheFailureCount() throws Exception {
        for (int i = 1; i <= 4; i++) {
            assertEquals(401, call("staff02", "guess" + i, "192.0.2.50"));
        }
        assertEquals(200, call("staff02", "pw-staff02", "192.0.2.51"));
        assertEquals(401, call("staff02", "guess5", "192.0.2.52"));
        assertEquals(429, call("staff02", "guess6", "192.0.2.53"));
    }

    @Test
    void anAddressLocksAfterTwentyFailuresAcrossAccounts() throws Exception {
        for (int i = 1; i <= 20; i++) {
            String user = "staff%02d".formatted(i);
            assertEquals(401, call(user, "wrong", "203.0.113.66"), "failure " + i);
        }
        assertEquals(429, call("staff21", "wrong", "203.0.113.66"));
        assertEquals(429, call("staff21", "pw-staff21", "203.0.113.66"), "no password check while locked");
        assertEquals(200, call("staff21", "pw-staff21", "203.0.113.67"), "other addresses are unaffected");
        clock.now = clock.now.plus(Duration.ofSeconds(61));
        assertEquals(200, call("staff21", "pw-staff21", "203.0.113.66"));
    }

    @Test
    void concurrentGuessesCannotOvershootTheAccountLimit() throws Exception {
        List<Callable<Integer>> guesses = new ArrayList<>();
        for (int i = 0; i < 24; i++) {
            String address = "198.51.100." + (100 + i);
            guesses.add(() -> call("staff03", "wrong", address));
        }
        int rejected = 0;
        int limited = 0;
        try (var pool = Executors.newFixedThreadPool(12)) {
            for (Future<Integer> f : pool.invokeAll(guesses)) {
                switch (f.get()) {
                    case 401 -> rejected++;
                    case 429 -> limited++;
                    default -> throw new AssertionError("unexpected status " + f.get());
                }
            }
        }
        assertEquals(5, rejected, "exactly five password checks may fail");
        assertEquals(19, limited);
    }
}
