package bff.ledger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class LedgerClientTest {
    @Test
    void fetchesTheAccountsStatementsWithTheServiceToken() {
        var builder = RestClient.builder().baseUrl("http://ledger.internal.test");
        var server = MockRestServiceServer.bindTo(builder).build();
        var client = new LedgerClient(builder.build(), "t0k3n");
        server.expect(requestTo("http://ledger.internal.test/accounts/acc-1/statements"))
                .andExpect(header("X-Service-Token", "t0k3n"))
                .andRespond(withSuccess("[]", MediaType.APPLICATION_JSON));
        assertEquals("[]", client.statements("acc-1"));
        server.verify();
    }
}
