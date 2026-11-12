CREATE TABLE users (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id  text        NOT NULL,
    email      text        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
