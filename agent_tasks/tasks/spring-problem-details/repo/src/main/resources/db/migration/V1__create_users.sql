CREATE TABLE users (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id    text        NOT NULL,
    email        text        NOT NULL,
    display_name text        NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX users_tenant_email_key ON users (tenant_id, lower(email));
