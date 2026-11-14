package ledger;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class AccessRulesTest {
    @Autowired
    MockMvc mvc;

    @Test
    void statusIsPublic() throws Exception {
        mvc.perform(get("/status")).andExpect(status().isOk());
    }

    @Test
    void accountsNeedASignedInUser() throws Exception {
        mvc.perform(get("/accounts")).andExpect(status().isUnauthorized());
        mvc.perform(get("/accounts").with(httpBasic("alice", "alice-pw"))).andExpect(status().isOk());
    }

    @Test
    void closingAnAccountNeedsAnAdmin() throws Exception {
        mvc.perform(delete("/accounts/2").with(httpBasic("alice", "alice-pw"))).andExpect(status().isForbidden());
        mvc.perform(delete("/accounts/2").with(httpBasic("root", "root-pw"))).andExpect(status().isNoContent());
    }
}
