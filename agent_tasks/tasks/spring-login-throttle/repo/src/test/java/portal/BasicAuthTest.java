package portal;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class BasicAuthTest {
    @Autowired
    MockMvc mvc;

    static String basic(String user, String password) {
        return "Basic " + Base64.getEncoder().encodeToString((user + ":" + password).getBytes(StandardCharsets.UTF_8));
    }

    @Test
    void pingIsPublic() throws Exception {
        mvc.perform(get("/public/ping")).andExpect(status().isOk());
    }

    @Test
    void rightPasswordGetsIn() throws Exception {
        mvc.perform(get("/api/me").header("Authorization", basic("alice", "alice-pw")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.user").value("alice"));
    }

    @Test
    void wrongPasswordIsRejected() throws Exception {
        mvc.perform(get("/api/me").header("Authorization", basic("staff40", "nope")))
                .andExpect(status().isUnauthorized());
    }
}
