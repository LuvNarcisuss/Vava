create or replace function public.get_catalog() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform app_private.viewer();
  return jsonb_build_object(
    'shorts', coalesce((select jsonb_agg(c.data order by c.position, c.id)
      from app_private.catalog c where c.kind = 'shorts'
      and exists (select 1 from storage.objects where bucket_id = 'catalog' and name = c.data->>'media')
      and exists (select 1 from storage.objects where bucket_id = 'catalog' and name = c.data->>'cover')), '[]'),
    'courses', coalesce((select jsonb_agg(
      case when (c.data->>'price')::integer = 0 then c.data || jsonb_build_object('steps', cc.steps)
      else c.data end order by c.position, c.id) from app_private.catalog c
      join app_private.course_content cc on cc.course = c.id where c.kind = 'courses'), '[]'),
    'replays', coalesce((select jsonb_agg(data order by position, id) from app_private.catalog where kind = 'replays'), '[]')
  );
end $$;
