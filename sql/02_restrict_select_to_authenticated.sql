-- =============================================================
-- health_metrics の閲覧(SELECT)をログイン済みユーザーのみに制限する。
-- INSERT/UPDATE は anon のまま(Health Auto Export からの自動送信を止めないため)
-- Supabase Dashboard の SQL Editor に貼り付けて実行する
-- =============================================================

drop policy if exists "allow select for anon" on public.health_metrics;

create policy "allow select for authenticated"
  on public.health_metrics for select
  to authenticated
  using (true);
