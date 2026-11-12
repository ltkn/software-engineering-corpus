package shop.users;

import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.endsWith;
import static org.hamcrest.Matchers.not;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import shop.CleanDatabase;

@SpringBootTest(properties = "spring.flyway.clean-disabled=false")
@AutoConfigureMockMvc
@Import(CleanDatabase.class)
class CreateUserTest {
    @Autowired
    MockMvc mvc;

    ResultActions create(String tenant, String json) throws Exception {
        return mvc.perform(post("/users").header("X-Tenant-Id", tenant)
                .contentType(MediaType.APPLICATION_JSON).content(json));
    }

    @Test
    void createdUserHasALocation() throws Exception {
        create("acme", "{\"email\":\"ann@acme.io\",\"displayName\":\"Ann\"}")
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", containsString("/users/")))
                .andExpect(jsonPath("$.displayName").value("Ann"));
    }

    @Test
    void invalidBodyListsEveryBadField() throws Exception {
        create("acme", "{\"email\":\"not-an-email\",\"displayName\":\"" + "x".repeat(101) + "\"}")
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.status").value(400))
                .andExpect(jsonPath("$.errors[*].field").value(containsInAnyOrder("email", "displayName")))
                .andExpect(jsonPath("$.errors[0].message").isNotEmpty());
    }

    @Test
    void missingFieldsAreBadRequestNotServerError() throws Exception {
        create("acme", "{}")
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.errors[*].field").value(containsInAnyOrder("email", "displayName")));
    }

    @Test
    void duplicateEmailIgnoringCaseIsAConflict() throws Exception {
        create("acme", "{\"email\":\"bob@acme.io\",\"displayName\":\"Bob\"}").andExpect(status().isCreated());
        create("acme", "{\"email\":\"Bob@ACME.io\",\"displayName\":\"Bobby\"}")
                .andExpect(status().isConflict())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.status").value(409))
                .andExpect(content().string(not(containsString("users_tenant_email_key"))))
                .andExpect(content().string(not(containsString("duplicate key"))))
                .andExpect(content().string(not(containsString("SQL"))));
    }

    @Test
    void sameEmailInAnotherTenantIsFine() throws Exception {
        create("acme", "{\"email\":\"cy@x.io\",\"displayName\":\"Cy\"}").andExpect(status().isCreated());
        create("globex", "{\"email\":\"cy@x.io\",\"displayName\":\"Cy\"}")
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", not(endsWith("/users/1"))));
    }
}
