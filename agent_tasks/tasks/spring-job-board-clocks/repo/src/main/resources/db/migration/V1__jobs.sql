CREATE TABLE jobs (
    id           bigserial PRIMARY KEY,
    name         text NOT NULL,
    started_at   timestamptz,
    finished_at  timestamptz,
    -- reported by the worker, from the worker's own clock
    heartbeat_at timestamptz,
    -- when this database stored the latest heartbeat
    received_at  timestamptz
);
