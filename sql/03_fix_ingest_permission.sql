-- =============================================================
-- 修正: ingest_health が auth.users を読めず "permission denied" に
-- なっていた問題の修正。
--
-- 原因: security invoker のままだと、実行者(iPhoneからのanonキー)の
-- 権限で動くため、auth.users(メールアドレス一覧)を覗く権限がない。
-- 対処: この関数だけに「特別な閲覧権限」を持たせる(security definer)。
-- anonロール自体には一切追加の権限を与えないので、
-- auth.usersが外部から丸見えになることはない。
-- Supabase Dashboard の SQL Editor に貼り付けて実行する
-- =============================================================

create or replace function public.ingest_health(data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  m jsonb;
  n integer;
  total integer := 0;
  target_user uuid;
begin
  select id into target_user from auth.users where email = 'heihachiro3@gmail.com';

  for m in select * from jsonb_array_elements(coalesce(data->'metrics', '[]'::jsonb))
  loop
    insert into health_metrics (recorded_date, metric_name, value, unit, raw, user_id)
    select
      left(p.value->>'date', 10)::date,
      m->>'name',
      case
        when m->>'units' in ('count','steps','km','mi','m','kcal','kJ','L','mL','g','mg','min')
          then sum((p.value->>'qty')::numeric)
        else avg((p.value->>'qty')::numeric)
      end,
      m->>'units',
      jsonb_agg(p.value order by p.value->>'date'),
      target_user
    from jsonb_array_elements(coalesce(m->'data', '[]'::jsonb)) p
    where p.value ? 'date'
    group by 1
    on conflict (recorded_date, metric_name, user_id) do update
      set value      = excluded.value,
          unit       = excluded.unit,
          raw        = excluded.raw,
          updated_at = now();

    get diagnostics n = row_count;
    total := total + n;
  end loop;

  return jsonb_build_object('status', 'ok', 'rows', total);
end;
$$;

grant execute on function public.ingest_health(jsonb) to anon;
