package feed;

import java.io.BufferedReader;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

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
 * trusted: every limit is charged while reading, before anything is built from the bytes, and the
 * announced count is only checked, never used to size anything.
 */
public final class Decoder {
    private final Limits limits;

    public Decoder(Limits limits) {
        this.limits = limits;
    }

    public Catalog decode(InputStream in) throws IOException, DecodeException {
        var budget = new ByteBudget(in, limits.maxBytes());
        var reader = new BufferedReader(new InputStreamReader(budget, StandardCharsets.UTF_8));
        Map<String, Category> byId = new HashMap<>();
        List<Category> rows = new ArrayList<>();
        try {
            String line;
            int lineNo = 0;
            while ((line = reader.readLine()) != null) {
                lineNo++;
                line = line.strip();
                if (lineNo == 1 && line.startsWith("#count ")) {
                    checkCount(line.substring(7).trim());
                    continue;
                }
                if (line.isEmpty()) {
                    continue;
                }
                if (rows.size() == limits.maxNodes()) {
                    throw new DecodeException("more than " + limits.maxNodes() + " categories");
                }
                String[] f = line.split(",", -1);
                if (f.length != 3 || f[0].isEmpty()) {
                    throw new DecodeException("line " + lineNo + ": expected id,parent,name");
                }
                Category c = new Category(f[0], f[1].isEmpty() ? null : f[1], f[2]);
                if (byId.putIfAbsent(c.id(), c) != null) {
                    throw new DecodeException("duplicate id " + c.id());
                }
                rows.add(c);
            }
        } catch (ByteBudget.Exceeded e) {
            throw new DecodeException("feed larger than " + limits.maxBytes() + " bytes");
        }
        checkTree(byId);
        return new Catalog(byId);
    }

    private void checkCount(String value) throws DecodeException {
        long count;
        try {
            count = Long.parseLong(value);
        } catch (NumberFormatException e) {
            throw new DecodeException("#count is not a number: " + value);
        }
        if (count < 0 || count > limits.maxNodes()) {
            throw new DecodeException("#count " + count + " outside 0.." + limits.maxNodes());
        }
    }

    /** Every parent exists, there is no cycle, and no category is more than maxDepth hops from its root. O(n). */
    private void checkTree(Map<String, Category> byId) throws DecodeException {
        Map<String, Integer> depth = new HashMap<>();
        for (Category start : byId.values()) {
            List<Category> walk = new ArrayList<>();
            Set<String> onWalk = new HashSet<>();
            Category c = start;
            int base;
            while (true) {
                Integer known = depth.get(c.id());
                if (known != null) {
                    base = known;
                    break;
                }
                if (!onWalk.add(c.id())) {
                    throw new DecodeException("parent cycle through category " + c.id());
                }
                walk.add(c);
                if (c.parent() == null) {
                    base = -1;
                    break;
                }
                Category parent = byId.get(c.parent());
                if (parent == null) {
                    throw new DecodeException("category " + c.id() + " has unknown parent " + c.parent());
                }
                if (walk.size() > limits.maxDepth() + 1) {
                    throw new DecodeException("category " + start.id() + " is more than " + limits.maxDepth()
                            + " levels deep");
                }
                c = parent;
            }
            for (int i = walk.size() - 1; i >= 0; i--) {
                base++;
                if (base > limits.maxDepth()) {
                    throw new DecodeException("category " + walk.get(i).id() + " is more than " + limits.maxDepth()
                            + " levels deep");
                }
                depth.put(walk.get(i).id(), base);
            }
        }
    }

    /** Fails the read as soon as more than {@code max} bytes have come through. */
    private static final class ByteBudget extends FilterInputStream {
        static final class Exceeded extends IOException {
        }

        private long left;

        ByteBudget(InputStream in, long max) {
            super(in);
            this.left = max;
        }

        @Override
        public int read() throws IOException {
            int b = super.read();
            if (b >= 0 && --left < 0) {
                throw new Exceeded();
            }
            return b;
        }

        @Override
        public int read(byte[] b, int off, int len) throws IOException {
            int n = super.read(b, off, (int) Math.min(len, Math.max(1, left + 1)));
            if (n > 0 && (left -= n) < 0) {
                throw new Exceeded();
            }
            return n;
        }
    }
}
