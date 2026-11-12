CREATE UNIQUE INDEX users_tenant_email_key ON users (tenant_id, lower(email));
