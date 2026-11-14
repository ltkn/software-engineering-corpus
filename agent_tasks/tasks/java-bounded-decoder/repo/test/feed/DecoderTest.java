package feed;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.junit.jupiter.api.Test;

class DecoderTest {
    static Catalog decode(String feed) throws Exception {
        return new Decoder(Limits.DEFAULT).decode(new ByteArrayInputStream(feed.getBytes(StandardCharsets.UTF_8)));
    }

    @Test
    void decodesATree() throws Exception {
        Catalog c = decode("#count 3\n1,,Kitchen\n2,1,Cookware\n3,2,Pans\n");
        assertEquals(3, c.size());
        assertEquals(List.of("Kitchen", "Cookware", "Pans"), c.path("3"));
    }

    @Test
    void theCountHeaderIsOptional() throws Exception {
        assertEquals(List.of("Garden"), decode("7,,Garden\n").path("7"));
    }

    @Test
    void anUnknownParentIsRejected() {
        assertThrows(DecodeException.class, () -> decode("1,9,Orphan\n"));
    }

    @Test
    void aMalformedRowIsRejected() {
        assertThrows(DecodeException.class, () -> decode("1,Kitchen\n"));
    }
}
