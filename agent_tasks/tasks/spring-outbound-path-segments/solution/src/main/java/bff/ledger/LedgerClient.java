package bff.ledger;

import java.util.Set;
import org.springframework.web.client.RestClient;

/** Calls the internal ledger service with the BFF's service token, which the ledger trusts fully. */
public class LedgerClient {
    /** Servers resolve these even percent-encoded (%2e%2e), so they cannot be sent at all. */
    private static final Set<String> NOT_A_SEGMENT = Set.of("", ".", "..");

    private final RestClient http;
    private final String serviceToken;

    public LedgerClient(RestClient http, String serviceToken) {
        this.http = http;
        this.serviceToken = serviceToken;
    }

    /** The account's statements as the ledger returns them (JSON). */
    public String statements(String accountId) {
        if (accountId == null || NOT_A_SEGMENT.contains(accountId)) {
            throw new IllegalArgumentException("not an account id: '" + accountId + "'");
        }
        // A URI variable is encoded as data: '/', '?', '#' and '%' stay inside the segment.
        return http.get()
                .uri("/accounts/{id}/statements", accountId)
                .header("X-Service-Token", serviceToken)
                .retrieve()
                .body(String.class);
    }
}
