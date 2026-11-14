package notes;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.concurrent.atomic.AtomicLong;
import notes.tenant.CurrentTenant;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.web.servlet.MockMvc;

/** A small pool: Hikari hands a thread back the connection it used last, so requests reuse one connection. */
@SpringBootTest(properties = {"spring.flyway.clean-disabled=false", "spring.datasource.hikari.maximum-pool-size=2"})
@AutoConfigureMockMvc
@Import(CleanDatabase.class)
class TenantIsolationTest {
    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcClient jdbc;

    @BeforeEach
    void seed() throws Exception {
        jdbc.sql("TRUNCATE notes RESTART IDENTITY").update();
        for (String title : new String[] {"a1", "a2"}) {
            mvc.perform(post("/notes").header("X-Tenant-Id", "acme")
                            .contentType(MediaType.APPLICATION_JSON).content("{\"title\":\"" + title + "\"}"))
                    .andExpect(status().isCreated());
        }
    }

    @Test
    void anotherTenantSeesNoneOfThem() throws Exception {
        mvc.perform(get("/notes").header("X-Tenant-Id", "globex"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
        mvc.perform(get("/notes").header("X-Tenant-Id", "acme"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(2));
    }

    @Test
    void aRequestWithoutATenantSeesNothing() throws Exception {
        mvc.perform(get("/notes").header("X-Tenant-Id", "acme")).andExpect(jsonPath("$.length()").value(2));
        mvc.perform(get("/notes")).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void theDatabaseFiltersEvenAQueryWithoutAWhereClause() {
        var seen = new AtomicLong(-1);
        CurrentTenant.runAs("globex", () ->
                seen.set(jdbc.sql("SELECT count(*) FROM notes").query(Long.class).single()));
        assertEquals(0, seen.get(), "row-level security must apply to the application's own connections");
        CurrentTenant.runAs("acme", () ->
                seen.set(jdbc.sql("SELECT count(*) FROM notes").query(Long.class).single()));
        assertEquals(2, seen.get());
    }

    @Test
    void codeWithNoTenantDoesNotInheritThePreviousOne() {
        CurrentTenant.runAs("acme", () -> jdbc.sql("SELECT count(*) FROM notes").query(Long.class).single());
        assertEquals(0, jdbc.sql("SELECT count(*) FROM notes").query(Long.class).single());
    }

    @Test
    void theAppliedMigrationIsUnchanged() throws Exception {
        byte[] v1 = Files.readAllBytes(Path.of("src/main/resources/db/migration/V1__notes.sql"));
        assertEquals("ce5525f0c4c4e7c58251da7ca965fdb032b9baf65efb45d714be0a8028068e9f", HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(v1)),
                "V1 is applied in production; add a new migration instead");
    }
}
