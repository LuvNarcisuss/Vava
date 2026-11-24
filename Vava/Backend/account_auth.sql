-- Apply only to the dedicated company Vava project.
begin;

create schema if not exists vava_private;
revoke all on schema vava_private from public, anon, authenticated;

-- Administrative aliases of the managed credentials. No second verifier is stored.
create or replace view vava_private.users with (security_invoker = true) as
select id, email as account, encrypted_password as password_hash
from auth.users;
revoke all on vava_private.users from public, anon, authenticated;

create or replace function vava_private.require_email()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
    if new.email is null or pg_catalog.octet_length(new.email) > 254
        or new.email !~ '^[^@[:space:]]+@[^@.[:space:]]+([.][^@.[:space:]]+)+$' then
        raise exception 'Enter a valid email address.' using errcode = '23514';
    end if;
    return new;
end;
$$;
revoke all on function vava_private.require_email() from public, anon, authenticated;
create or replace trigger vava_require_email before insert or update of email on auth.users
for each row execute function vava_private.require_email();

commit;
