package ops.jobs;

import java.time.LocalDate;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
class JobController {
    private final JobBoard board;

    JobController(JobBoard board) {
        this.board = board;
    }

    @GetMapping("/jobs/active")
    List<JobView> active() {
        return board.active();
    }

    @GetMapping("/jobs/day")
    List<JobView> day(@RequestParam LocalDate date) {
        return board.day(date);
    }
}
