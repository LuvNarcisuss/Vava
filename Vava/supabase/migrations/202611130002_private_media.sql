create function public.my_submission_objects() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare who uuid := app_private.viewer();
begin
  return coalesce((select jsonb_agg(name order by name) from storage.objects
    where bucket_id = 'submissions' and (storage.foldername(name))[1] = who::text), '[]');
end $$;

create function public.get_submission_path(submission_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare who uuid := app_private.viewer(); path_value text;
begin
  select path into path_value from app_private.submissions where id = submission_id and owner = who;
  if path_value is null then raise exception 'invalid_submission'; end if;
  return to_jsonb(path_value);
end $$;

revoke all on function public.my_submission_objects(), public.get_submission_path(uuid) from public, anon, authenticated;
grant execute on function public.my_submission_objects(), public.get_submission_path(uuid) to authenticated;
