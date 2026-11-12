-- PostgreSQL does not index foreign keys automatically. On a large live table,
-- run CREATE INDEX CONCURRENTLY in a migration without a transaction instead.
CREATE INDEX order_lines_order_id_idx ON order_lines (order_id);
