package epg;

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

    /** When the programme airs. */
    public static Instant start(Schedule schedule, Schedule.Entry entry) {
        return schedule.day().atStartOfDay().plusMinutes(entry.minutes()).atZone(schedule.zone()).toInstant();
    }

    /** The schedule as a viewer in {@code viewerZone} sees it. */
    public static List<Listing> listings(Schedule schedule, ZoneId viewerZone) {
        return schedule.entries().stream()
                .map(e -> new Listing(schedule.channel(), e.title(),
                        schedule.day().atStartOfDay().plusMinutes(e.minutes())))
                .toList();
    }
}
