-- =============================================================
-- 新指標の取り込み対応:
-- ・sleep_analysis: qtyを持たず、1晩ごとに段階別(合計/コア/深い/REM/起きている)の
--   時間(hr)を持つ特殊な構造 → sleep_total/sleep_core/sleep_deep/sleep_rem/sleep_awake
--   の5つの指標に分けて保存する
-- ・heart_rate: qtyではなくAvg/Min/Maxを持つ特殊な構造 → heart_rate(平均)/
--   heart_rate_min/heart_rate_max の3つに分けて保存する
-- それ以外(歩数・安静時心拍数・心拍変動・歩行系)は既存の汎用ロジック(qtyベース)のまま
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
  s jsonb;
  stage record;
  n integer;
  total integer := 0;
  target_user uuid;
begin
  select id into target_user from auth.users where email = 'heihachiro3@gmail.com';

  for m in select * from jsonb_array_elements(coalesce(data->'metrics', '[]'::jsonb))
  loop

    if m->>'name' = 'sleep_analysis' then
      -- 睡眠: 1晩ごとの段階別データを複数指標に分解
      for s in select * from jsonb_array_elements(coalesce(m->'data', '[]'::jsonb))
      loop
        for stage in
          select * from (values
            ('sleep_total', 'totalSleep'),
            ('sleep_core',  'core'),
            ('sleep_deep',  'deep'),
            ('sleep_rem',   'rem'),
            ('sleep_awake', 'awake')
          ) as t(metric_name, json_key)
        loop
          insert into health_metrics (recorded_date, metric_name, value, unit, raw, user_id)
          values (
            left(s->>'date', 10)::date,
            stage.metric_name,
            (s->>stage.json_key)::numeric,
            'hr',
            s,
            target_user
          )
          on conflict (recorded_date, metric_name, user_id) do update
            set value = excluded.value, unit = excluded.unit, raw = excluded.raw, updated_at = now();
          total := total + 1;
        end loop;
      end loop;

    elsif m->>'name' = 'heart_rate' then
      -- 心拍数: qtyではなくAvg/Min/Maxを持つため個別に展開
      for s in select * from jsonb_array_elements(coalesce(m->'data', '[]'::jsonb))
      loop
        for stage in
          select * from (values
            ('heart_rate',     'Avg'),
            ('heart_rate_min', 'Min'),
            ('heart_rate_max', 'Max')
          ) as t(metric_name, json_key)
        loop
          insert into health_metrics (recorded_date, metric_name, value, unit, raw, user_id)
          values (
            left(s->>'date', 10)::date,
            stage.metric_name,
            (s->>stage.json_key)::numeric,
            'count/min',
            s,
            target_user
          )
          on conflict (recorded_date, metric_name, user_id) do update
            set value = excluded.value, unit = excluded.unit, raw = excluded.raw, updated_at = now();
          total := total + 1;
        end loop;
      end loop;

    else
      -- それ以外: 既存の汎用ロジック(qtyベース、日次で合計 or 平均)
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
    end if;

  end loop;

  return jsonb_build_object('status', 'ok', 'rows', total);
end;
$$;

grant execute on function public.ingest_health(jsonb) to anon;
