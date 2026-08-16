-- =============================================================
-- 指標名一覧の取得方法を、テーブル全件取得からRPC関数に変更する。
--
-- 背景: これまでダッシュボードは health_metrics の全行から metric_name
-- 列だけ取得し、画面側で重複を除いていた。しかしSupabaseはAPI応答の
-- 行数にサーバー側の上限(既定1000行)があり、クライアント側で
-- .limit()を大きくしても上限は超えられない。データが増えるにつれ
-- (現在約1,700行)、アルファベット順で後ろの指標(sleep_total等)が
-- 上限を超えて欠落する不具合が発生した。
--
-- 対処: 「自分の指標名の一覧だけ」をサーバー側で絞り込んで返す
-- RPC関数を用意する。返す行数は指標の種類数(十数件)だけなので、
-- 今後データが何年分増えても上限に引っかからない。
-- Supabase Dashboard の SQL Editor に貼り付けて実行する
-- =============================================================

create or replace function public.list_metric_names()
returns table (metric_name text)
language sql
security invoker
set search_path = public
as $$
  select distinct metric_name
  from health_metrics
  where user_id = auth.uid()
  order by metric_name;
$$;

grant execute on function public.list_metric_names() to authenticated;
