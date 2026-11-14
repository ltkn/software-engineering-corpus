package epg;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;
import org.junit.jupiter.api.Test;

class ZonesTest {
    static Schedule oslo(String day, String... rows) {
        return Schedule.parse("channel: nordic-one\nzone: Europe/Oslo\nday: " + day + "\n" + String.join("\n", rows) + "\n");
    }

    static List<Instant> starts(Schedule s) {
        return s.entries().stream().map(e -> Guide.start(s, e)).toList();
    }

    static List<LocalDateTime> seenIn(Schedule s, String zone) {
        return Guide.listings(s, ZoneId.of(zone)).stream().map(Guide.Listing::start).toList();
    }

    @Test
    void aNormalDayAirsAtTheChannelsLocalTimes() {
        var s = oslo("2026-11-14", "06:00 Morning News", "25:15 Night Music");
        assertEquals(List.of(Instant.parse("2026-11-14T05:00:00Z"), Instant.parse("2026-11-15T00:15:00Z")), starts(s));
        assertEquals(List.of(LocalDateTime.parse("2026-11-14T06:00"), LocalDateTime.parse("2026-11-15T01:15")),
                seenIn(s, "Europe/Oslo"));
    }

    @Test
    void viewersElsewhereSeeTheirOwnClock() {
        var s = oslo("2026-11-14", "05:30 Early News", "06:00 Morning News");
        assertEquals(List.of(LocalDateTime.parse("2026-11-14T04:30"), LocalDateTime.parse("2026-11-14T05:00")),
                seenIn(s, "Europe/London"));
        assertEquals(List.of(LocalDateTime.parse("2026-11-13T23:30"), LocalDateTime.parse("2026-11-14T00:00")),
                seenIn(s, "America/New_York"));
    }

    @Test
    void theDaySummerTimeEndsHasTwentyFiveHours() {
        // 2026-10-25: Oslo goes from UTC+2 back to UTC+1 at 01:00 UTC.
        var s = oslo("2026-10-25", "01:30 Night Music", "03:30 Early News", "24:30 Late Film");
        assertEquals(List.of(Instant.parse("2026-10-24T23:30:00Z"), Instant.parse("2026-10-25T01:30:00Z"),
                Instant.parse("2026-10-25T22:30:00Z")), starts(s));
        assertEquals(List.of(LocalDateTime.parse("2026-10-25T01:30"), LocalDateTime.parse("2026-10-25T02:30"),
                LocalDateTime.parse("2026-10-25T23:30")), seenIn(s, "Europe/Oslo"));
    }

    @Test
    void theDaySummerTimeStartsHasTwentyThreeHours() {
        // 2026-03-29: Oslo goes from UTC+1 to UTC+2 at 01:00 UTC.
        var s = oslo("2026-03-29", "04:00 Early News", "23:30 Late Film");
        assertEquals(List.of(Instant.parse("2026-03-29T03:00:00Z"), Instant.parse("2026-03-29T22:30:00Z")), starts(s));
        assertEquals(List.of(LocalDateTime.parse("2026-03-29T05:00"), LocalDateTime.parse("2026-03-30T00:30")),
                seenIn(s, "Europe/Oslo"));
        assertEquals(List.of(LocalDateTime.parse("2026-03-29T04:00"), LocalDateTime.parse("2026-03-29T23:30")),
                seenIn(s, "Europe/London"));
    }
}
