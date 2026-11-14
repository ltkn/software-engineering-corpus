package feed;

/**
 * Bounds on one feed: total bytes, number of categories, and how many parent hops a category may
 * be from its root.
 */
public record Limits(int maxBytes, int maxNodes, int maxDepth) {
    public static final Limits DEFAULT = new Limits(1_000_000, 10_000, 64);
}
