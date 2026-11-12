package shop.reports;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import shop.tenant.TenantContext;

@RestController
public class ReportController {
    public record Report(String tenant, List<String> sections) {
    }

    private static final List<String> SECTIONS = List.of("sales", "stock", "returns");

    private final SectionLoader loader;

    public ReportController(SectionLoader loader) {
        this.loader = loader;
    }

    @GetMapping("/reports/daily")
    public Report daily() throws InterruptedException, ExecutionException {
        // Scoped values are not inherited by executor threads (only by StructuredTaskScope,
        // still a preview API), so each task binds the caller's tenant itself.
        String tenant = TenantContext.current();
        try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            List<Future<String>> parts = SECTIONS.stream()
                    .map(s -> executor.submit(() -> TenantContext.callAs(tenant, () -> loader.load(s))))
                    .toList();
            List<String> sections = new ArrayList<>();
            for (var part : parts) {
                sections.add(part.get());
            }
            return new Report(tenant, sections);
        }
    }
}
