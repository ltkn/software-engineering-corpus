CREATE TABLE invoices (
    id           bigserial PRIMARY KEY,
    customer     text   NOT NULL,
    amount_cents bigint NOT NULL
);

CREATE SEQUENCE audit_log_seq;

CREATE TABLE audit_log (
    id       bigint PRIMARY KEY DEFAULT nextval('audit_log_seq'),
    action   text        NOT NULL,
    ref      text        NOT NULL,
    recorded timestamptz NOT NULL DEFAULT now()
);
