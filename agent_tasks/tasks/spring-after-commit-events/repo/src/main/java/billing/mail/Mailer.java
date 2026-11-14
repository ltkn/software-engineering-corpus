package billing.mail;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import org.springframework.stereotype.Component;

/** Stand-in for the mail provider: keeps what was sent. */
@Component
public class Mailer {
    private final List<String> sent = new CopyOnWriteArrayList<>();

    public void send(String to, String text) {
        sent.add(to + ": " + text);
    }

    public List<String> sent() {
        return List.copyOf(sent);
    }

    public void clear() {
        sent.clear();
    }
}
