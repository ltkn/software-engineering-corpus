package shop.users;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import shop.CleanDatabase;

@SpringBootTest(properties = "spring.flyway.clean-disabled=false")
@AutoConfigureMockMvc
@Import(CleanDatabase.class)
class UserApiTest {
    @Autowired
    MockMvc mvc;

    long create(String json, String expectedName) throws Exception {
        var res = mvc.perform(post("/users").header("X-Tenant-Id", "acme")
                        .contentType(MediaType.APPLICATION_JSON).content(json))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.displayName").value(expectedName))
                .andReturn();
        return ((Number) JsonPath.read(res.getResponse().getContentAsString(), "$.id")).longValue();
    }

    @Test
    void displayNameDefaultsToTheEmailLocalPart() throws Exception {
        long id = create("{\"email\":\"carol.diaz@acme.io\"}", "carol.diaz");
        mvc.perform(get("/users/" + id).header("X-Tenant-Id", "acme"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.displayName").value("carol.diaz"));
    }

    @Test
    void displayNameCanBeGiven() throws Exception {
        long id = create("{\"email\":\"dan@acme.io\",\"displayName\":\"Dan K.\"}", "Dan K.");
        mvc.perform(get("/users/" + id).header("X-Tenant-Id", "acme"))
                .andExpect(jsonPath("$.displayName").value("Dan K."));
    }
}
