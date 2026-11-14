package epg;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;

/**
 * One channel's schedule for one broadcast day, as channels publish it:
 *
 * <pre>
 * channel: nordic-one
 * zone: Europe/Oslo
 * day: 2026-11-14
 * 06:00 Morning News
 * 23:30 Late Film
 * 25:15 Night Music
 * </pre>
 *
 * Per the format specification, each time is the elapsed time since the start of the broadcast day
 * (local midnight in the channel's zone). It may exceed 24:00: those programmes air after midnight
 * but belong to this broadcast day.
 */
public record Schedule(String channel, ZoneId zone, LocalDate day, List<Entry> entries) {
    /** A programme, {@code minutes} after the start of the broadcast day. */
    public record Entry(String title, int minutes) {
    }

    public static Schedule parse(String text) {
        String channel = null;
        ZoneId zone = null;
        LocalDate day = null;
        List<Entry> entries = new ArrayList<>();
        for (String raw : text.split("\n")) {
            String line = raw.strip();
            if (line.isEmpty()) {
                continue;
            }
            if (line.startsWith("channel:")) {
                channel = line.substring(8).strip();
            } else if (line.startsWith("zone:")) {
                zone = ZoneId.of(line.substring(5).strip());
            } else if (line.startsWith("day:")) {
                day = LocalDate.parse(line.substring(4).strip());
            } else {
                int space = line.indexOf(' ');
                String[] hm = line.substring(0, space).split(":");
                entries.add(new Entry(line.substring(space + 1).strip(),
                        Integer.parseInt(hm[0]) * 60 + Integer.parseInt(hm[1])));
            }
        }
        if (channel == null || zone == null || day == null) {
            throw new IllegalArgumentException("schedule needs channel, zone and day");
        }
        return new Schedule(channel, zone, day, List.copyOf(entries));
    }
}
