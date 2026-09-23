-- Runs once, on first init. The image creates these roles; this sets their passwords.
\set pgpass `echo "$POSTGRES_PASSWORD"`
alter user authenticator with password :'pgpass';
alter user supabase_auth_admin with password :'pgpass';
