package epg;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;
import org.junit.jupiter.api.Test;

class GuideTest {
    static final String OSLO = """
            channel: nordic-one
            zone: Europe/Oslo
            day: 2026-11-14
            06:00 Morning News
            23:30 Late Film
            """;

    @Test
    void parsesTheHeaderAndEntries() {
        Schedule s = Schedule.parse(OSLO);
        assertEquals("nordic-one", s.channel());
        assertEquals(List.of(new Schedule.Entry("Morning News", 360), new Schedule.Entry("Late Film", 1410)), s.entries());
    }

    @Test
    void aViewerInTheChannelsZoneSeesThePublishedTimes() {
        var listings = Guide.listings(Schedule.parse(OSLO), ZoneId.of("Europe/Oslo"));
        assertEquals(LocalDateTime.parse("2026-11-14T06:00"), listings.get(0).start());
        assertEquals(LocalDateTime.parse("2026-11-14T23:30"), listings.get(1).start());
    }
}
