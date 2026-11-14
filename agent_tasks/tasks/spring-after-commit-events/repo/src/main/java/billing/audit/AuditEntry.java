package billing.audit;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.SequenceGenerator;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "audit_log")
public class AuditEntry {
    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "audit_log")
    @SequenceGenerator(name = "audit_log", sequenceName = "audit_log_seq", allocationSize = 1)
    private Long id;

    @Column(nullable = false)
    private String action;

    @Column(nullable = false)
    private String ref;

    @Column(nullable = false)
    private Instant recorded;

    protected AuditEntry() {
    }

    public AuditEntry(String action, String ref, Instant recorded) {
        this.action = action;
        this.ref = ref;
        this.recorded = recorded;
    }

    public Long getId() {
        return id;
    }

    public String getAction() {
        return action;
    }

    public String getRef() {
        return ref;
    }
}
