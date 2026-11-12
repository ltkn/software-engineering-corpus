package shop.reports;

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
        try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            List<Future<String>> parts = SECTIONS.stream()
                    .map(s -> executor.submit(() -> loader.load(s)))
                    .toList();
            var sections = new java.util.ArrayList<String>();
            for (var part : parts) {
                sections.add(part.get());
            }
            return new Report(TenantContext.current(), sections);
        }
    }
}
