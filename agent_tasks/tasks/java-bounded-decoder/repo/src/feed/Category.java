package feed;

/** One row of the feed. {@code parent} is null for a root category. */
public record Category(String id, String parent, String name) {
}
