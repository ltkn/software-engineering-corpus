package catalog.products;

/** An amount in minor units (cents) of an ISO 4217 currency. */
public record Money(long minor, String currency) {
    public String display() {
        return "%d.%02d %s".formatted(minor / 100, Math.abs(minor % 100), currency);
    }
}
