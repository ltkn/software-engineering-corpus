package ops.jobs;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

@Service
public class JobBoard {
    public static final long STALE_AFTER_SECONDS = 60;

    record Row(long id, String name, OffsetDateTime startedAt, OffsetDateTime heartbeatAt) {
    }

    private final JdbcClient jdbc;
    private final Clock clock;

    public JobBoard(JdbcClient jdbc, Clock clock) {
        this.jdbc = jdbc;
        this.clock = clock;
    }

    /** Jobs that have not finished yet. */
    public List<JobView> active() {
        return jdbc.sql("""
                SELECT id, name, started_at, heartbeat_at
                FROM jobs WHERE finished_at IS NULL ORDER BY id""").query(Row.class).list()
                .stream().map(this::view).toList();
    }

    /** Every job that started on the given day (UTC), finished or not. */
    public List<JobView> day(LocalDate day) {
        return jdbc.sql("""
                SELECT id, name, started_at, heartbeat_at
                FROM jobs WHERE (started_at AT TIME ZONE 'UTC')::date = ? ORDER BY id""")
                .param(day).query(Row.class).list()
                .stream().map(this::view).toList();
    }

    private JobView view(Row r) {
        Instant now = clock.instant();
        boolean inProgress = r.startedAt() != null && !r.startedAt().toInstant().isAfter(now);
        Long age = r.heartbeatAt() == null ? null : Duration.between(r.heartbeatAt().toInstant(), now).toSeconds();
        return new JobView(r.id(), r.name(), inProgress, age, age != null && age > STALE_AFTER_SECONDS);
    }
}
