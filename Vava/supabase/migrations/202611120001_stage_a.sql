create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;

create table app_private.players (
  id uuid primary key references auth.users on delete cascade,
  code text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)),
  name text not null default 'Table tennis player' check (length(name) between 1 and 40),
  bio text not null default '' check (length(bio) <= 180)
);
create table app_private.consent (
  player uuid primary key references app_private.players on delete cascade,
  revision text not null,
  accepted_at timestamptz not null default now()
);
create table app_private.catalog (
  id text primary key,
  kind text not null check (kind in ('shorts', 'courses', 'replays')),
  position integer not null,
  data jsonb not null check (data ->> 'id' = id)
);
create table app_private.course_content (
  course text primary key references app_private.catalog on delete cascade,
  steps jsonb not null check (jsonb_typeof(steps) = 'array')
);
create table app_private.activity (
  player uuid not null references app_private.players on delete cascade,
  target text not null references app_private.catalog on delete cascade,
  kind text not null check (kind in ('like', 'save', 'hide')),
  primary key (player, target, kind)
);
create table app_private.practice (
  player uuid not null references app_private.players on delete cascade,
  course text not null references app_private.course_content on delete cascade,
  step integer not null,
  primary key (player, course, step)
);
create table app_private.relationships (
  source uuid not null references app_private.players on delete cascade,
  target uuid not null references app_private.players on delete cascade,
  kind text not null check (kind in ('follow', 'block')),
  check (source <> target),
  primary key (source, target, kind)
);
create index relationships_target_idx on app_private.relationships (target, kind, source);
create table app_private.discussions (
  id uuid primary key,
  clip text not null references app_private.catalog on delete cascade,
  author uuid not null references app_private.players on delete cascade,
  body text not null check (length(body) between 1 and 200),
  reply_to uuid references app_private.discussions on delete set null,
  created_at timestamptz not null default now()
);
create index discussions_clip_idx on app_private.discussions (clip, created_at desc, id);
create table app_private.reports (
  id uuid primary key default gen_random_uuid(),
  reporter uuid not null references app_private.players on delete cascade,
  target text not null,
  kind text not null check (kind in ('clip', 'replay', 'comment', 'player')),
  reason text not null check (length(reason) between 1 and 240),
  created_at timestamptz not null default now(),
  unique (reporter, kind, target)
);
create table app_private.threads (
  id uuid primary key default gen_random_uuid(),
  first_player uuid not null references app_private.players on delete cascade,
  second_player uuid not null references app_private.players on delete cascade,
  check (first_player < second_player),
  unique (first_player, second_player)
);
create index threads_second_idx on app_private.threads (second_player);
create table public.messages (
  id uuid primary key,
  thread uuid not null references app_private.threads on delete cascade,
  sender uuid not null references app_private.players on delete cascade,
  body text not null check (length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index messages_thread_idx on public.messages (thread, created_at desc, id desc);
create table app_private.reads (
  player uuid not null references app_private.players on delete cascade,
  thread uuid not null references app_private.threads on delete cascade,
  read_at timestamptz not null,
  primary key (player, thread)
);
create table app_private.submissions (
  id uuid primary key,
  owner uuid not null references app_private.players on delete cascade,
  title text not null check (length(title) between 1 and 80),
  path text not null unique,
  status text not null default 'Private submission' check (status = 'Private submission'),
  created_at timestamptz not null default now()
);
create index submissions_owner_idx on app_private.submissions (owner, created_at desc);
alter table public.messages enable row level security;
revoke all on public.messages from public, anon, authenticated;
grant select on public.messages to authenticated;
alter publication supabase_realtime add table public.messages;

create function app_private.viewer() returns uuid language plpgsql stable security definer set search_path = '' as $$
declare who uuid := auth.uid();
begin
  if who is null or not exists (
    select 1 from app_private.consent c where c.player = who and c.revision = '2026-11-12.1'
  ) then raise exception 'consent_required'; end if;
  return who;
end $$;

create function app_private.is_blocked(a uuid, b uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from app_private.relationships r where r.kind = 'block'
    and ((r.source = a and r.target = b) or (r.source = b and r.target = a)))
$$;

create function public.can_read_message(thread_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from app_private.threads t join app_private.consent c on c.player = auth.uid() and c.revision = '2026-11-12.1'
    where t.id = thread_id and auth.uid() in (t.first_player, t.second_player)
      and not app_private.is_blocked(t.first_player, t.second_player)
  )
$$;

create policy "Participants read messages" on public.messages
for select to authenticated using (public.can_read_message(thread));

create function public.bootstrap(revision text, accepted boolean) returns jsonb language plpgsql security definer set search_path = '' as $$
declare who uuid := auth.uid();
begin
  if who is null or not exists (select 1 from auth.users where id = who) then
    raise exception 'consent_required';
  end if;
  if revision is distinct from '2026-11-12.1' then raise exception 'consent_required'; end if;
  if accepted is true then
    insert into app_private.players (id) values (who) on conflict (id) do nothing;
    insert into app_private.consent as c (player, revision) values (who, bootstrap.revision)
      on conflict (player) do update set revision = excluded.revision, accepted_at = now()
      where c.revision is distinct from excluded.revision;
  end if;
  perform app_private.viewer();
  return '{"ok":true,"data":{}}'::jsonb;
end $$;

create function public.get_catalog() returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform app_private.viewer();
  return jsonb_build_object(
    'shorts', coalesce((select jsonb_agg(data order by position, id) from app_private.catalog where kind = 'shorts'), '[]'),
    'courses', coalesce((select jsonb_agg(
      case when (data->>'price')::integer = 0 then data || jsonb_build_object('steps', cc.steps) else data end
      order by c.position, c.id) from app_private.catalog c
      join app_private.course_content cc on cc.course = c.id where c.kind = 'courses'), '[]'),
    'replays', coalesce((select jsonb_agg(data order by position, id) from app_private.catalog where kind = 'replays'), '[]')
  );
end $$;

create function public.get_course_steps(course_id text) returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform app_private.viewer();
  return coalesce((select steps from app_private.course_content where course = course_id), '[]');
end $$;

create function public.get_state() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  return jsonb_build_object(
    'me', (select to_jsonb(p) from app_private.players p where p.id = who),
    'following', coalesce((select jsonb_agg(to_jsonb(p) order by p.name, p.id)
      from app_private.relationships r join app_private.players p on p.id = r.target
      where r.source = who and r.kind = 'follow' and not app_private.is_blocked(who, p.id)), '[]'),
    'followers', coalesce((select jsonb_agg(to_jsonb(p) order by p.name, p.id)
      from app_private.relationships r join app_private.players p on p.id = r.source
      where r.target = who and r.kind = 'follow' and not app_private.is_blocked(who, p.id)), '[]'),
    'blocked', coalesce((select jsonb_agg(to_jsonb(p) order by p.name, p.id)
      from app_private.relationships r join app_private.players p on p.id = r.target
      where r.source = who and r.kind = 'block'), '[]'),
    'likes', coalesce((select jsonb_agg(target) from app_private.activity where player = who and kind = 'like'), '[]'),
    'saves', coalesce((select jsonb_agg(target) from app_private.activity where player = who and kind = 'save'), '[]'),
    'hidden', coalesce((select jsonb_agg(target) from app_private.activity where player = who and kind = 'hide'), '[]'),
    'practice', coalesce((select jsonb_object_agg(course, steps) from (
      select course, jsonb_agg(step order by step) steps from app_private.practice where player = who group by course
    ) grouped), '{}')
  );
end $$;

create function public.set_activity(target text, kind text, enabled boolean) returns jsonb language plpgsql security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  if kind not in ('like', 'save', 'hide') then raise exception 'invalid_activity'; end if;
  if enabled then
    insert into app_private.activity values (who, target, kind) on conflict do nothing;
  else
    delete from app_private.activity a where a.player = who and a.target = set_activity.target and a.kind = set_activity.kind;
  end if;
  return '{"ok":true}'::jsonb;
end $$;

create function public.set_practice(course_id text, step_index integer, completed boolean) returns jsonb language plpgsql security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  if step_index < 0 or not exists (
    select 1 from app_private.course_content where course = course_id and step_index < jsonb_array_length(steps)
  ) then raise exception 'invalid_step'; end if;
  if completed then
    insert into app_private.practice values (who, course_id, step_index) on conflict do nothing;
  else
    delete from app_private.practice where player = who and course = course_id and step = step_index;
  end if;
  return '{"ok":true}'::jsonb;
end $$;

create function public.update_profile(display_name text, biography text) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  update app_private.players set name = btrim(display_name), bio = btrim(biography) where id = app_private.viewer();
  return '{"ok":true}'::jsonb;
end $$;

create function public.find_player(player_code text) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  return coalesce((select jsonb_agg(to_jsonb(p)) from app_private.players p
    where p.code = upper(btrim(player_code)) and p.id <> who and not app_private.is_blocked(who, p.id)), '[]');
end $$;

create function public.get_player(player_id uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  return coalesce((select jsonb_agg(to_jsonb(p)) from app_private.players p
    where p.id = player_id and not app_private.is_blocked(who, p.id)), '[]');
end $$;

create function public.set_relationship(peer uuid, kind text, enabled boolean) returns jsonb language plpgsql security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  if peer = who or kind not in ('follow', 'block') or not exists (select 1 from app_private.players where id = peer) then
    raise exception 'player_unavailable';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(who, peer)::text || greatest(who, peer)::text, 0));
  if kind = 'follow' and enabled and app_private.is_blocked(who, peer) then raise exception 'player_unavailable'; end if;
  if enabled then
    insert into app_private.relationships values (who, peer, kind) on conflict do nothing;
    if kind = 'block' then
      delete from app_private.relationships r where r.kind = 'follow'
        and ((r.source = who and r.target = peer) or (r.source = peer and r.target = who));
    end if;
  else
    delete from app_private.relationships r where r.source = who and r.target = peer and r.kind = set_relationship.kind;
  end if;
  return '{"ok":true}'::jsonb;
end $$;

create function public.get_discussion(clip_id text, before_id uuid default null) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'author', to_jsonb(p), 'body', d.body,
    'replyTo', d.reply_to, 'createdAt', d.created_at) order by d.created_at desc, d.id desc)
    from (select * from app_private.discussions c where c.clip = clip_id
      and not app_private.is_blocked(who, c.author)
      and not exists (select 1 from app_private.reports r where r.reporter = who and r.kind = 'comment' and r.target = c.id::text)
      and (before_id is null or (c.created_at, c.id) < (select b.created_at, b.id from app_private.discussions b where b.id = before_id and b.clip = clip_id))
      order by c.created_at desc, c.id desc limit 50) d join app_private.players p on p.id = d.author), '[]');
end $$;

create function public.post_comment(clip_id text, comment_id uuid, text_body text, parent uuid default null) returns jsonb language plpgsql security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  if not exists (select 1 from app_private.catalog where id = clip_id and kind = 'shorts')
    or (parent is not null and not exists (select 1 from app_private.discussions
       where id = parent and clip = clip_id and not app_private.is_blocked(who, author)))
  then raise exception 'invalid_comment'; end if;
  insert into app_private.discussions values (comment_id, clip_id, who, btrim(text_body), parent, now())
    on conflict (id) do nothing;
  if not exists (select 1 from app_private.discussions where id = comment_id and author = who and clip = clip_id
    and body = btrim(text_body) and reply_to is not distinct from parent) then raise exception 'invalid_comment'; end if;
  return '{"ok":true}'::jsonb;
end $$;

create function public.submit_report(target_id text, target_kind text, reason_text text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  if not (
    (target_kind in ('clip', 'replay') and exists (select 1 from app_private.catalog
      where id = target_id and kind = case when target_kind = 'clip' then 'shorts' else 'replays' end))
    or (target_kind = 'comment' and exists (select 1 from app_private.discussions where id::text = lower(target_id) and author <> who))
    or (target_kind = 'player' and exists (select 1 from app_private.players where id::text = lower(target_id) and id <> who))
  ) then raise exception 'invalid_report'; end if;
  insert into app_private.reports (reporter, target, kind, reason)
    values (who, lower(target_id), target_kind, btrim(reason_text)) on conflict (reporter, kind, target) do nothing;
  if target_kind in ('clip', 'replay') then
    insert into app_private.activity values (who, target_id, 'hide') on conflict do nothing;
  end if;
  return '{"ok":true}'::jsonb;
end $$;

create function app_private.require_mutual(a uuid, b uuid) returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if a = b or app_private.is_blocked(a, b) or not exists (
    select 1 from app_private.relationships where source = a and target = b and kind = 'follow'
  ) or not exists (
    select 1 from app_private.relationships where source = b and target = a and kind = 'follow'
  ) then raise exception 'mutual_follow_required'; end if;
end $$;

create function public.open_thread(peer uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare who uuid := app_private.viewer(); thread_id uuid;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(who, peer)::text || greatest(who, peer)::text, 0));
  perform app_private.require_mutual(who, peer);
  insert into app_private.threads (first_player, second_player) values (least(who, peer), greatest(who, peer))
    on conflict (first_player, second_player) do nothing;
  select id into strict thread_id from app_private.threads where first_player = least(who, peer) and second_player = greatest(who, peer);
  return (select jsonb_build_object('id', thread_id, 'peer', to_jsonb(p), 'unread', false) from app_private.players p where p.id = peer);
end $$;

create function public.list_threads() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', t.id, 'peer', to_jsonb(p), 'preview', m.body,
    'unread', coalesce(m.sender <> who and m.created_at > coalesce(r.read_at, '-infinity'), false)
  ) order by m.created_at desc nulls last, t.id)
  from app_private.threads t join app_private.players p
    on p.id = case when t.first_player = who then t.second_player else t.first_player end
  left join lateral (
    select body, sender, created_at from public.messages where thread = t.id order by created_at desc, id desc limit 1
  ) m on true
  left join app_private.reads r on r.thread = t.id and r.player = who
  where who in (t.first_player, t.second_player) and not app_private.is_blocked(t.first_player, t.second_player)), '[]');
end $$;

create function public.get_messages(thread_id uuid, before_id uuid default null) returns jsonb language plpgsql security definer set search_path = '' as $$
declare who uuid := app_private.viewer(); result jsonb; latest timestamptz;
begin
  if not public.can_read_message(thread_id) then raise exception 'player_unavailable'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'sender', m.sender, 'body', m.body,
    'createdAt', m.created_at) order by m.created_at desc, m.id desc), '[]'), max(m.created_at) into result, latest
  from (select * from public.messages where thread = thread_id
    and (before_id is null or (created_at, id) < (select b.created_at, b.id from public.messages b where b.id = before_id and b.thread = thread_id))
    order by created_at desc, id desc limit 50) m;
  if before_id is null and latest is not null then
    insert into app_private.reads as r values (who, thread_id, latest)
      on conflict (player, thread) do update set read_at = greatest(r.read_at, excluded.read_at);
  end if;
  return result;
end $$;

create function public.send_message(thread_id uuid, message_id uuid, text_body text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare who uuid := app_private.viewer(); t app_private.threads%rowtype;
begin
  select * into t from app_private.threads where id = thread_id and who in (first_player, second_player);
  if t.id is null then raise exception 'player_unavailable'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(t.first_player::text || t.second_player::text, 0));
  perform app_private.require_mutual(t.first_player, t.second_player);
  insert into public.messages (id, thread, sender, body)
    values (message_id, thread_id, who, btrim(text_body)) on conflict (id) do nothing;
  if not exists (select 1 from public.messages where id = message_id and sender = who and thread = thread_id and body = btrim(text_body))
  then raise exception 'invalid_message'; end if;
  return '{"ok":true}'::jsonb;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('catalog', 'catalog', true, 30000000, array['video/mp4', 'image/jpeg']),
  ('agreements', 'agreements', true, 5000000, array['application/pdf']),
  ('submissions', 'submissions', false, 50000000, array['video/mp4'])
on conflict (id) do nothing;

create policy "Private submission upload" on storage.objects for insert to authenticated with check (
  bucket_id = 'submissions' and (storage.foldername(name))[1] = auth.uid()::text
  and storage.extension(name) = 'mp4'
);
create policy "Private submission read" on storage.objects for select to authenticated using (
  bucket_id = 'submissions' and (storage.foldername(name))[1] = auth.uid()::text
);
create policy "Private submission removal" on storage.objects for delete to authenticated using (
  bucket_id = 'submissions' and (storage.foldername(name))[1] = auth.uid()::text
);

create function public.register_submission(submission_id uuid, video_title text, object_path text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  if object_path <> who::text || '/' || submission_id::text || '.mp4'
    or not exists (select 1 from storage.objects where bucket_id = 'submissions' and name = object_path)
  then raise exception 'invalid_submission'; end if;
  insert into app_private.submissions (id, owner, title, path) values (submission_id, who, btrim(video_title), object_path)
    on conflict (id) do nothing;
  if not exists (select 1 from app_private.submissions where id = submission_id and owner = who
    and path = object_path and title = btrim(video_title)) then raise exception 'invalid_submission'; end if;
  return '{"ok":true}'::jsonb;
end $$;

create function public.my_submissions() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'path', path, 'status', status)
    order by created_at desc) from app_private.submissions where owner = who), '[]');
end $$;

create function public.remove_submission(submission_id uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  delete from app_private.submissions where id = submission_id and owner = app_private.viewer()
    and not exists (select 1 from storage.objects where bucket_id = 'submissions' and name = path);
  return '{"ok":true}'::jsonb;
end $$;

create function public.delete_my_account() returns jsonb language plpgsql security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  if exists (select 1 from storage.objects where owner_id = who::text) then raise exception 'remove_private_media'; end if;
  delete from auth.users where id = who;
  return '{"ok":true}'::jsonb;
end $$;

do $$
declare signature text;
begin
  for signature in select p.oid::regprocedure::text from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
    and p.proname = any(array['bootstrap','get_catalog','get_course_steps','get_state','set_activity','set_practice',
      'update_profile','find_player','get_player','set_relationship','get_discussion','post_comment','submit_report',
      'can_read_message','open_thread','list_threads','get_messages','send_message',
      'register_submission','my_submissions','remove_submission','delete_my_account'])
  loop
    execute 'revoke all on function ' || signature || ' from public, anon, authenticated';
    execute 'grant execute on function ' || signature || ' to authenticated';
  end loop;
end $$;

revoke all on all functions in schema app_private from public, anon, authenticated;
