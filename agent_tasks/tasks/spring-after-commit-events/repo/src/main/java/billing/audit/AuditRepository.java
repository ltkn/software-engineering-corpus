package billing.audit;

import org.springframework.data.jpa.repository.JpaRepository;

interface AuditRepository extends JpaRepository<AuditEntry, Long> {
}
