create or replace function app_private.viewer() returns uuid language plpgsql stable security definer set search_path = '' as $$
declare who uuid := auth.uid();
begin
  if who is null or not exists (
    select 1 from app_private.consent c where c.player = who and c.revision = '2026-11-13.1'
  ) then raise exception 'consent_required'; end if;
  return who;
end $$;

create or replace function public.can_read_message(thread_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from app_private.threads t join app_private.consent c on c.player = auth.uid() and c.revision = '2026-11-13.1'
    where t.id = thread_id and auth.uid() in (t.first_player, t.second_player)
      and not app_private.is_blocked(t.first_player, t.second_player)
  )
$$;

create or replace function public.bootstrap(revision text, accepted boolean) returns jsonb language plpgsql security definer set search_path = '' as $$
declare who uuid := auth.uid();
begin
  if who is null or not exists (select 1 from auth.users where id = who) then
    raise exception 'consent_required';
  end if;
  if revision is distinct from '2026-11-13.1' then raise exception 'consent_required'; end if;
  if accepted is true then
    insert into app_private.players (id) values (who) on conflict (id) do nothing;
    insert into app_private.consent as c (player, revision) values (who, bootstrap.revision)
      on conflict (player) do update set revision = excluded.revision, accepted_at = now()
      where c.revision is distinct from excluded.revision;
  end if;
  perform app_private.viewer();
  return '{"ok":true,"data":{}}'::jsonb;
end $$;

create function public.has_current_upload_consent() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from app_private.consent
    where player = auth.uid() and revision = '2026-11-13.1'
  ) and exists (select 1 from storage.buckets where id = 'submissions' and public)
$$;

revoke all on function public.has_current_upload_consent() from public, anon, authenticated;
grant execute on function public.has_current_upload_consent() to authenticated;

alter policy "Private submission upload" on storage.objects with check (
  bucket_id = 'submissions' and (storage.foldername(name))[1] = auth.uid()::text
  and storage.extension(name) = 'mp4' and public.has_current_upload_consent()
);
