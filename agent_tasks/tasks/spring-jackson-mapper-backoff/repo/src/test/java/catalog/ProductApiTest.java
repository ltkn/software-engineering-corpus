package catalog;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class ProductApiTest {
    @Autowired
    MockMvc mvc;

    @Test
    void pricesUseTheStorefrontFormat() throws Exception {
        mvc.perform(get("/products/p-2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Kettle"))
                .andExpect(jsonPath("$.price").value("39.99 EUR"));
    }
}
