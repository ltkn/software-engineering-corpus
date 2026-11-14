package ledger.access;

public enum Audience {
    /** Anyone, signed in or not. */
    PUBLIC,
    /** Any signed-in user. */
    USER,
    /** Signed-in administrators only. */
    ADMIN
}
