package stock;

public class InsufficientStock extends RuntimeException {
    public InsufficientStock(String sku, int wanted, int available) {
        super("wanted " + wanted + " of " + sku + ", " + available + " available");
    }
}
