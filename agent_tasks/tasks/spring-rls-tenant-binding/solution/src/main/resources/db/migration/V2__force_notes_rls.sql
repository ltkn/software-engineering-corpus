-- The application connects as the table owner, and owners bypass row-level
-- security unless it is forced.
ALTER TABLE notes FORCE ROW LEVEL SECURITY;
