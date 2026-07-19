-- =============================================================
-- ヘルスケアダッシュボード: テーブル + 受け口RPC関数
-- Supabase Dashboard の SQL Editor に全文貼り付けて実行する
-- (何度実行してもエラーにならないよう if not exists / or replace で記述)
-- =============================================================

-- 日付×指標のロング形式。raw に元データを保持する
create table if not exists public.health_metrics (
  id bigint generated always as identity primary key,
  recorded_date date not null,          -- 記録日(端末のローカル日付)
  metric_name text not null,            -- 例: step_count
  value numeric,                        -- 日次の値(qtyが無い指標はnull、rawを参照)
  unit text,                            -- 例: count
  raw jsonb,                            -- その日の元データ点(配列)
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique (recorded_date, metric_name)   -- 同日・同指標は1行 → 再送はUPSERTで上書き
);

alter table public.health_metrics enable row level security;

-- 自宅用途のため anon キーに読み書きを許可。
-- 絞りたくなったら to anon を to authenticated に変えてログイン必須にする
drop policy if exists "allow select for anon" on public.health_metrics;
create policy "allow select for anon"
  on public.health_metrics for select to anon using (true);

drop policy if exists "allow insert for anon" on public.health_metrics;
create policy "allow insert for anon"
  on public.health_metrics for insert to anon with check (true);

drop policy if exists "allow update for anon" on public.health_metrics;
create policy "allow update for anon"
  on public.health_metrics for update to anon
  using (true) with check (true);  -- with check が無いとUPSERT時の更新が拒否される

-- -------------------------------------------------------------
-- 受け口: Health Auto Export の入れ子JSONを展開して日次UPSERTする関数
-- 送信先URL: https://<プロジェクトID>.supabase.co/rest/v1/rpc/ingest_health
-- (POSTボディのトップレベルキー "data" がそのまま引数 data に渡る)
-- -------------------------------------------------------------
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
begin
  for m in select * from jsonb_array_elements(coalesce(data->'metrics', '[]'::jsonb))
  loop
    insert into health_metrics (recorded_date, metric_name, value, unit, raw)
    select
      -- 日付は "2026-07-13 01:12:00 +0900" の先頭10文字(端末ローカルの日付)。
      -- timestamptz経由でdate化するとUTC換算で日付がずれるため文字列から取る
      left(p.value->>'date', 10)::date,
      m->>'name',
      -- 1日に複数点あるとき: 加算が意味を持つ単位(歩数・距離・カロリー等)は合計、
      -- それ以外(心拍数・体温・割合等)は平均
      case
        when m->>'units' in ('count','steps','km','mi','m','kcal','kJ','L','mL','g','mg','min')
          then sum((p.value->>'qty')::numeric)
        else avg((p.value->>'qty')::numeric)
      end,
      m->>'units',
      jsonb_agg(p.value order by p.value->>'date')
    from jsonb_array_elements(coalesce(m->'data', '[]'::jsonb)) p
    where p.value ? 'date'
    group by 1
    on conflict (recorded_date, metric_name) do update
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
