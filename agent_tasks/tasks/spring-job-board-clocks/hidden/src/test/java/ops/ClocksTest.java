package ops;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Clock;
import java.time.Duration;
import java.time.LocalDate;
import java.util.List;
import ops.jobs.JobBoard;
import ops.jobs.JobView;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.simple.JdbcClient;

/** This app server's clock runs ten minutes ahead of the database. */
@SpringBootTest(properties = "spring.flyway.clean-disabled=false")
@Import({CleanDatabase.class, ClocksTest.Skew.class})
class ClocksTest {
    @TestConfiguration(proxyBeanMethods = false)
    static class Skew {
        @Bean
        @Primary
        Clock skewedClock() {
            return Clock.offset(Clock.systemUTC(), Duration.ofMinutes(10));
        }
    }

    @Autowired
    JobBoard board;

    @Autowired
    JdbcClient jdbc;

    @BeforeEach
    void empty() {
        jdbc.sql("TRUNCATE jobs RESTART IDENTITY").update();
    }

    private long job(String name, String startedAt, String finishedAt, String heartbeatAt, String receivedAt) {
        return jdbc.sql("INSERT INTO jobs (name, started_at, finished_at, heartbeat_at, received_at) VALUES (?, "
                        + startedAt + ", " + finishedAt + ", " + heartbeatAt + ", " + receivedAt + ") RETURNING id")
                .param(name).query(Long.class).single();
    }

    private static JobView find(List<JobView> views, long id) {
        return views.stream().filter(v -> v.id() == id).findFirst().orElseThrow(() -> new AssertionError("job " + id + " missing"));
    }

    @Test
    void aFinishedJobIsNotInProgressInTheDayView() {
        long done = job("export", "now() - interval '2 hours'", "now() - interval '1 hour'",
                "now() - interval '1 hour'", "now() - interval '1 hour'");
        LocalDate day = jdbc.sql("SELECT (started_at AT TIME ZONE 'UTC')::date FROM jobs WHERE id = ?")
                .param(done).query(LocalDate.class).single();
        assertFalse(find(board.day(day), done).inProgress());
    }

    @Test
    void aJobThatHasNotStartedYetIsNotInProgress() {
        long later = job("rollup", "now() + interval '5 minutes'", "NULL", "NULL", "NULL");
        assertFalse(find(board.active(), later).inProgress());
    }

    @Test
    void aRunningJobIsInProgressInBothViews() {
        long running = job("reindex", "now() - interval '1 minute'", "NULL",
                "now() - interval '20 seconds'", "now() - interval '20 seconds'");
        LocalDate day = jdbc.sql("SELECT (started_at AT TIME ZONE 'UTC')::date FROM jobs WHERE id = ?")
                .param(running).query(LocalDate.class).single();
        assertTrue(find(board.active(), running).inProgress());
        assertTrue(find(board.day(day), running).inProgress());
    }

    @Test
    void ageIsMeasuredOnTheDatabaseClock() {
        long running = job("reindex", "now() - interval '1 minute'", "NULL",
                "now() - interval '20 seconds'", "now() - interval '20 seconds'");
        JobView v = find(board.active(), running);
        assertNotNull(v.ageSeconds());
        assertTrue(v.ageSeconds() >= 15 && v.ageSeconds() <= 45, "age " + v.ageSeconds());
        assertFalse(v.stale());
    }

    @Test
    void aWorkerClaimingTheFutureIsAsOldAsItsLastReceivedHeartbeat() {
        long frozen = job("ingest", "now() - interval '1 hour'", "NULL",
                "now() + interval '15 minutes'", "now() - interval '2 minutes'");
        JobView v = find(board.active(), frozen);
        assertNotNull(v.ageSeconds());
        assertTrue(v.ageSeconds() >= 110 && v.ageSeconds() <= 150, "age " + v.ageSeconds());
        assertTrue(v.stale());
    }

    @Test
    void aJobThatNeverReportedHasNoAge() {
        long silent = job("queued", "now() - interval '1 minute'", "NULL", "NULL", "NULL");
        JobView v = find(board.active(), silent);
        assertEquals(null, v.ageSeconds());
        assertFalse(v.stale());
    }
}
