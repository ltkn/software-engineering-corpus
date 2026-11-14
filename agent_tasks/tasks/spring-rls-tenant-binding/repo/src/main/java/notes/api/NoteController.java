package notes.api;

import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
class NoteController {
    record Note(long id, String title) {
    }

    record NewNote(String title) {
    }

    private final JdbcClient jdbc;

    NoteController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** Row-level security decides which notes the caller sees. */
    @GetMapping("/notes")
    List<Note> list() {
        return jdbc.sql("SELECT id, title FROM notes ORDER BY id").query(Note.class).list();
    }

    @PostMapping("/notes")
    @ResponseStatus(HttpStatus.CREATED)
    Note create(@RequestBody NewNote note) {
        return jdbc.sql("""
                INSERT INTO notes (tenant_id, title)
                VALUES (current_setting('app.current_tenant'), ?)
                RETURNING id, title""").param(note.title()).query(Note.class).single();
    }
}
