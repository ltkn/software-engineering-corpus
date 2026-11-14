package feed;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/** A decoded category tree. */
public final class Catalog {
    private final Map<String, Category> byId;

    Catalog(Map<String, Category> byId) {
        this.byId = Map.copyOf(byId);
    }

    public int size() {
        return byId.size();
    }

    /** Names from the root down to {@code id}, e.g. [Kitchen, Cookware, Pans]. */
    public List<String> path(String id) {
        Category c = byId.get(id);
        if (c == null) {
            throw new IllegalArgumentException("unknown category " + id);
        }
        List<String> names = new ArrayList<>();
        if (c.parent() != null) {
            names.addAll(path(c.parent()));
        }
        names.add(c.name());
        return Collections.unmodifiableList(names);
    }
}
