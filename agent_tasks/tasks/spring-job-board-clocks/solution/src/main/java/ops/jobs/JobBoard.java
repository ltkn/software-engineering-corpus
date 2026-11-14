package ops.jobs;

import java.time.LocalDate;
import java.util.List;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

/**
 * Everything time-dependent is computed by the database, on its own clock: app-server clocks
 * drift. "In progress" is defined once, with both edges, and every view selects that definition.
 * A worker's heartbeat_at is its claim; it never counts as newer than received_at, our own
 * observation of it.
 */
@Service
public class JobBoard {
    public static final long STALE_AFTER_SECONDS = 60;

    private static final String COLUMNS = """
            SELECT id, name,
                   (started_at IS NOT NULL AND started_at <= now()
                    AND (finished_at IS NULL OR finished_at > now())) AS in_progress,
                   floor(extract(epoch FROM now() - least(heartbeat_at, received_at)))::bigint AS age_seconds
            FROM jobs
            """;

    record Row(long id, String name, boolean inProgress, Long ageSeconds) {
    }

    private final JdbcClient jdbc;

    public JobBoard(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** Jobs that have not finished yet. */
    public List<JobView> active() {
        return jdbc.sql(COLUMNS + "WHERE finished_at IS NULL ORDER BY id").query(Row.class).list()
                .stream().map(JobBoard::view).toList();
    }

    /** Every job that started on the given day (UTC), finished or not. */
    public List<JobView> day(LocalDate day) {
        return jdbc.sql(COLUMNS + "WHERE (started_at AT TIME ZONE 'UTC')::date = ? ORDER BY id")
                .param(day).query(Row.class).list()
                .stream().map(JobBoard::view).toList();
    }

    private static JobView view(Row r) {
        Long age = r.ageSeconds();
        return new JobView(r.id(), r.name(), r.inProgress(), age, age != null && age > STALE_AFTER_SECONDS);
    }
}
