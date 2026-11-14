package feed;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import org.junit.jupiter.api.Test;

class HostileFeedTest {
    static final Duration QUICKLY = Duration.ofSeconds(10);

    static Catalog decode(Limits limits, String feed) throws Exception {
        return new Decoder(limits).decode(new ByteArrayInputStream(feed.getBytes(StandardCharsets.UTF_8)));
    }

    /** An upload that never ends: the given row pattern forever, with fresh ids. */
    static InputStream endless(boolean newlines) {
        return new InputStream() {
            long n;
            byte[] pending = new byte[0];
            int pos;

            @Override
            public int read() {
                if (pos == pending.length) {
                    n++;
                    pending = (newlines ? n + ",,x\n" : "aaaaaaaaaaaaaaaa").getBytes(StandardCharsets.US_ASCII);
                    pos = 0;
                }
                return pending[pos++];
            }

            @Override
            public int read(byte[] b, int off, int len) {
                for (int i = 0; i < len; i++) {
                    b[off + i] = (byte) read();
                }
                return len;
            }
        };
    }

    @Test
    void aHugeAnnouncedCountIsRejectedWithoutAllocatingForIt() {
        assertTimeoutPreemptively(QUICKLY, () ->
                assertThrows(DecodeException.class, () -> decode(Limits.DEFAULT, "#count 2147483000\n1,,A\n")));
    }

    @Test
    void aNegativeOrGarbledCountIsRejected() {
        assertThrows(DecodeException.class, () -> decode(Limits.DEFAULT, "#count -5\n1,,A\n"));
        assertThrows(DecodeException.class, () -> decode(Limits.DEFAULT, "#count lots\n1,,A\n"));
    }

    @Test
    void anEndlessFeedOfRowsStopsAtALimit() {
        assertTimeoutPreemptively(QUICKLY, () ->
                assertThrows(DecodeException.class, () -> new Decoder(Limits.DEFAULT).decode(endless(true))));
    }

    @Test
    void anEndlessLineStopsAtTheByteLimit() {
        assertTimeoutPreemptively(QUICKLY, () ->
                assertThrows(DecodeException.class, () -> new Decoder(Limits.DEFAULT).decode(endless(false))));
    }

    @Test
    void theCategoryBudgetIsExact() throws Exception {
        Limits limits = new Limits(1_000_000, 100, 64);
        StringBuilder feed = new StringBuilder();
        for (int i = 1; i <= 100; i++) {
            feed.append(i).append(",,c").append(i).append('\n');
        }
        assertEquals(100, decode(limits, feed.toString()).size());
        feed.append("101,,c101\n");
        assertThrows(DecodeException.class, () -> decode(limits, feed.toString()));
    }

    @Test
    void theByteBudgetIsEnforced() throws Exception {
        Limits limits = new Limits(40, 100, 64);
        String fits = "1,,Kitchen\n2,1,Cookware\n3,2,Pans\n";   // 33 bytes
        assertEquals(3, decode(limits, fits).size());
        assertThrows(DecodeException.class, () -> decode(limits, fits + "4,3,Woks\n"));
    }

    @Test
    void parentCyclesAreRejectedQuickly() {
        assertTimeoutPreemptively(QUICKLY, () -> {
            assertThrows(DecodeException.class, () -> decode(Limits.DEFAULT, "1,1,Self\n"));
            assertThrows(DecodeException.class, () -> decode(Limits.DEFAULT, "1,2,A\n2,1,B\n"));
            assertThrows(DecodeException.class, () -> decode(Limits.DEFAULT, "0,,Root\n1,3,A\n2,1,B\n3,2,C\n4,0,D\n"));
        });
    }

    @Test
    void depthIsCountedInParentHops() throws Exception {
        Limits limits = new Limits(1_000_000, 10_000, 64);
        StringBuilder chain = new StringBuilder("0,,c0\n");
        for (int i = 1; i <= 64; i++) {
            chain.append(i).append(',').append(i - 1).append(",c").append(i).append('\n');
        }
        assertEquals(65, decode(limits, chain.toString()).path("64").size());
        chain.append("65,64,c65\n");
        assertThrows(DecodeException.class, () -> decode(limits, chain.toString()));
    }

    @Test
    void manyDeepCategoriesDecodeInLinearTime() {
        Limits limits = new Limits(10_000_000, 10_000, 10_000);
        StringBuilder chain = new StringBuilder("0,,c0\n");
        for (int i = 1; i < 10_000; i++) {
            chain.append(i).append(',').append(i - 1).append(",c").append(i).append('\n');
        }
        assertTimeoutPreemptively(Duration.ofSeconds(5), () ->
                assertEquals(10_000, decode(limits, chain.toString()).path("9999").size()));
    }
}
