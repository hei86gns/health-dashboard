-- =============================================================
-- 家族の各メンバーが「自分の健康データだけ」を見られるようにする。
-- ・health_metrics に「誰のデータか」を示す user_id 列を追加
-- ・SELECTはRLSで「自分の行だけ」に制限
-- ・INSERT/UPDATE は anon のまま(Health Auto Export からの自動送信を止めないため)
-- ・ingest_health のURL・iPhone側の設定は変更不要(中身だけ差し替え)
-- Supabase Dashboard の SQL Editor に貼り付けて実行する
-- =============================================================

-- 1. 「誰のデータか」を示す列を追加
alter table public.health_metrics
  add column if not exists user_id uuid references auth.users(id);

-- 2. 既存データ(あなたのテスト送信分)を自分のアカウントに紐付け
update public.health_metrics
set user_id = (select id from auth.users where email = 'heihachiro3@gmail.com')
where user_id is null;

-- 3. 今後は必須にする
alter table public.health_metrics
  alter column user_id set not null;

-- 4. 重複防止の一意制約を user_id 込みに変更
--    (元の unique(recorded_date, metric_name) を、自動生成された名前によらず安全に探して削除)
do $$
declare
  c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.health_metrics'::regclass
      and contype = 'u'
      and array_length(conkey, 1) = 2
  loop
    execute format('alter table public.health_metrics drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.health_metrics
  add constraint health_metrics_date_metric_user_key
  unique (recorded_date, metric_name, user_id);

-- 5. 閲覧(SELECT)は「自分の行だけ」に制限
drop policy if exists "allow select for anon" on public.health_metrics;
drop policy if exists "allow select for authenticated" on public.health_metrics;

create policy "allow select own rows"
  on public.health_metrics for select
  to authenticated
  using (auth.uid() = user_id);

-- 6. ingest_health を「あなたのアカウントに紐付けて書き込む」ように更新
--    (iPhone側のURL・ヘッダー設定は一切変更不要)
create or replace function public.ingest_health(data jsonb)
returns jsonb
language plpgsql
security invoker
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

-- =============================================================
-- 家族2人目・3人目を追加するとき(今は実行不要・将来のひな形):
--
-- create or replace function public.ingest_health_2(data jsonb)
-- returns jsonb language plpgsql security invoker set search_path = public as $$
-- declare m jsonb; n integer; total integer := 0; target_user uuid;
-- begin
--   select id into target_user from auth.users where email = '2人目のメールアドレス';
--   -- (以降はingest_healthと同じ処理)
--   ...
-- end; $$;
-- grant execute on function public.ingest_health_2(jsonb) to anon;
--
-- 2人目のiPhoneのHealth Auto Exportでは、URL欄を
-- .../rest/v1/rpc/ingest_health_2 に変える(あなたのURLはそのまま)
-- =============================================================
