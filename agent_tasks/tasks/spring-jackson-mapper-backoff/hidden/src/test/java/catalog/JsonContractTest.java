package catalog;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class JsonContractTest {
    @Autowired
    MockMvc mvc;

    @Test
    void absentValuesAreOmitted() throws Exception {
        mvc.perform(get("/products/p-1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.description").doesNotExist())
                .andExpect(jsonPath("$.price").value("12.50 EUR"));
    }

    @Test
    void unknownRequestFieldsAreRejected() throws Exception {
        mvc.perform(put("/products/p-2/name").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Cup\",\"colour\":\"red\"}"))
                .andExpect(status().isBadRequest());
        mvc.perform(get("/products/p-2")).andExpect(jsonPath("$.name").value("Kettle"));
    }

    @Test
    void knownRequestFieldsStillWork() throws Exception {
        mvc.perform(put("/products/p-2/name").contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Teapot\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Teapot"))
                .andExpect(jsonPath("$.price").value("39.99 EUR"));
    }

    @Test
    void problemPropertiesAreTopLevelMembers() throws Exception {
        mvc.perform(get("/products/nope"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("product.not_found"))
                .andExpect(jsonPath("$.properties").doesNotExist())
                .andExpect(jsonPath("$.type").doesNotExist());
    }
}
