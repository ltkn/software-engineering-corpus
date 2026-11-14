package bff.ledger;

import org.springframework.web.client.RestClient;

/** Calls the internal ledger service with the BFF's service token, which the ledger trusts fully. */
public class LedgerClient {
    private final RestClient http;
    private final String serviceToken;

    public LedgerClient(RestClient http, String serviceToken) {
        this.http = http;
        this.serviceToken = serviceToken;
    }

    /** The account's statements as the ledger returns them (JSON). */
    public String statements(String accountId) {
        return http.get()
                .uri("/accounts/" + accountId + "/statements")
                .header("X-Service-Token", serviceToken)
                .retrieve()
                .body(String.class);
    }
}
