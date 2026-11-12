package shop.users;

public record User(long id, String tenantId, String email, String displayName) {
}
