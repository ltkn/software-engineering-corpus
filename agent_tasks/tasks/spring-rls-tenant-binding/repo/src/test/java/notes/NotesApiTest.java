package notes;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest(properties = "spring.flyway.clean-disabled=false")
@AutoConfigureMockMvc
@Import(CleanDatabase.class)
class NotesApiTest {
    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcClient jdbc;

    @BeforeEach
    void empty() {
        jdbc.sql("TRUNCATE notes RESTART IDENTITY").update();
    }

    @Test
    void aTenantSeesTheNotesItCreated() throws Exception {
        mvc.perform(post("/notes").header("X-Tenant-Id", "acme")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"title\":\"plan\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.title").value("plan"));
        mvc.perform(get("/notes").header("X-Tenant-Id", "acme"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].title").value("plan"));
    }
}
