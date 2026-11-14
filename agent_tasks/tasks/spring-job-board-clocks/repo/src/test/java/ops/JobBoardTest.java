package ops;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest(properties = "spring.flyway.clean-disabled=false")
@AutoConfigureMockMvc
@Import(CleanDatabase.class)
class JobBoardTest {
    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcClient jdbc;

    @BeforeEach
    void seed() {
        jdbc.sql("TRUNCATE jobs RESTART IDENTITY").update();
        jdbc.sql("""
                INSERT INTO jobs (name, started_at, heartbeat_at, received_at)
                VALUES ('reindex', now() - interval '1 minute', now() - interval '10 seconds', now() - interval '10 seconds')
                """).update();
    }

    @Test
    void aRunningJobWithARecentHeartbeatIsInProgressAndFresh() throws Exception {
        mvc.perform(get("/jobs/active"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].inProgress").value(true))
                .andExpect(jsonPath("$[0].stale").value(false));
    }
}
