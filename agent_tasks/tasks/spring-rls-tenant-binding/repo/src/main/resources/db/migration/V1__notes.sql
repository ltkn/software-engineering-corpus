-- Applied in production. Isolation is enforced by row-level security: the
-- application never filters by tenant itself.
CREATE TABLE notes (
    id        bigserial PRIMARY KEY,
    tenant_id text NOT NULL,
    title     text NOT NULL
);

ALTER TABLE notes ENABLE ROW LEVEL SECURITY;

CREATE POLICY notes_tenant ON notes
    USING (tenant_id = current_setting('app.current_tenant', true));
