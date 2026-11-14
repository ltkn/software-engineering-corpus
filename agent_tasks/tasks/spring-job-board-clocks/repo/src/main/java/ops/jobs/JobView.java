package ops.jobs;

/**
 * One job on the status board. {@code ageSeconds} is how long ago the worker last reported
 * (null when it never did); {@code stale} means more than {@link JobBoard#STALE_AFTER_SECONDS}.
 */
public record JobView(long id, String name, boolean inProgress, Long ageSeconds, boolean stale) {
}
