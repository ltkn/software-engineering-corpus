package feed;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Decodes a supplier's category feed:
 *
 * <pre>
 * #count 3
 * 1,,Kitchen
 * 2,1,Cookware
 * 3,2,Pans
 * </pre>
 *
 * The optional {@code #count} header announces the number of rows. Each row is
 * {@code id,parent,name}; an empty parent marks a root. The feed comes from outside and is not
 * trusted.
 */
public final class Decoder {
    private final Limits limits;

    public Decoder(Limits limits) {
        this.limits = limits;
    }

    public Catalog decode(InputStream in) throws IOException, DecodeException {
        byte[] bytes = in.readAllBytes();
        if (bytes.length > limits.maxBytes()) {
            throw new DecodeException("feed larger than " + limits.maxBytes() + " bytes");
        }
        String[] lines = new String(bytes, StandardCharsets.UTF_8).split("\n");
        List<Category> rows = new ArrayList<>();
        int start = 0;
        if (lines.length > 0 && lines[0].startsWith("#count ")) {
            rows = new ArrayList<>(Integer.parseInt(lines[0].substring(7).trim()));
            start = 1;
        }
        for (int i = start; i < lines.length; i++) {
            String line = lines[i].strip();
            if (line.isEmpty()) {
                continue;
            }
            String[] f = line.split(",", -1);
            if (f.length != 3 || f[0].isEmpty()) {
                throw new DecodeException("line " + (i + 1) + ": expected id,parent,name");
            }
            rows.add(new Category(f[0], f[1].isEmpty() ? null : f[1], f[2]));
        }
        Map<String, Category> byId = new HashMap<>();
        for (Category c : rows) {
            if (byId.putIfAbsent(c.id(), c) != null) {
                throw new DecodeException("duplicate id " + c.id());
            }
        }
        for (Category c : rows) {
            if (c.parent() != null && !byId.containsKey(c.parent())) {
                throw new DecodeException("category " + c.id() + " has unknown parent " + c.parent());
            }
        }
        return new Catalog(byId);
    }
}
