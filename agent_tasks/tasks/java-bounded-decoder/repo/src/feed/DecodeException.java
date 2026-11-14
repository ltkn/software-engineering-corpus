package feed;

/** The feed is malformed or exceeds a limit; nothing from it is used. */
public class DecodeException extends Exception {
    public DecodeException(String message) {
        super(message);
    }
}
