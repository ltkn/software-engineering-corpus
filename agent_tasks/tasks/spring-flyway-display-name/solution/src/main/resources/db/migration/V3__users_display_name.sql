-- Add as nullable, backfill, then require it: works on a populated table.
ALTER TABLE users ADD COLUMN display_name text;

UPDATE users SET display_name = split_part(email, '@', 1) WHERE display_name IS NULL;

ALTER TABLE users ALTER COLUMN display_name SET NOT NULL;
