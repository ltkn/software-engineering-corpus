package epg;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;

/** Turns published schedules into the programme guide viewers see. */
public final class Guide {
    /** A programme as shown to a viewer: start in the viewer's local time. */
    public record Listing(String channel, String title, LocalDateTime start) {
    }

    private Guide() {
    }

    /**
     * When the programme airs: the format measures elapsed time from the start of the broadcast
     * day in the channel's zone, so on a summer-time switch day "03:30" is not the 03:30 on the
     * wall clock.
     */
    public static Instant start(Schedule schedule, Schedule.Entry entry) {
        return schedule.day().atStartOfDay(schedule.zone()).toInstant().plus(Duration.ofMinutes(entry.minutes()));
    }

    /** The schedule as a viewer in {@code viewerZone} sees it: the airing instant on their own clock. */
    public static List<Listing> listings(Schedule schedule, ZoneId viewerZone) {
        return schedule.entries().stream()
                .map(e -> new Listing(schedule.channel(), e.title(),
                        LocalDateTime.ofInstant(start(schedule, e), viewerZone)))
                .toList();
    }
}
