# ヘルスケアダッシュボード 開発メモ

## 目的
iPhoneの「Health Auto Export - JSON+CSV」アプリから、REST APIオートメーション機能を使って
Apple Healthの各種指標をSupabaseに自動送信し、Supabase上に蓄積されたデータを
単一HTMLファイルのダッシュボードで可視化する。

## 全体構成

```
iPhone (Health Auto Export)
  └─ REST APIオートメーション(定期実行)
       └─ POST → Supabase REST API
                    └─ health_metrics テーブル
                         └─ index.html(ダッシュボード)が SELECT して表示
```

## 現状(2026/07/19時点)
- Health Auto Exportをインストール済み、試用期間中
- 「新しいオートメーション」画面(自動化の種類: REST API)まで到達
  - URL欄・ヘッダー欄が未入力の状態
  - 「健康メトリックを選択」で送信する指標を選べる
  - エクスポート形式: JSON, バージョン: v2
- **実際に送信されるJSONの構造はまだ未確認**
  - 一度、適当な受け先(webhook.siteなど)に試験送信して構造を確認するか、
    Supabase側に緩いテーブル(jsonb列で受ける)を先に作ってから調整するのが安全

## Supabase テーブル設計(叩き台)

構造が未確定なため、まずは「ロング形式」+「生JSON保持」のハイブリッドで受ける案。

```sql
create table if not exists health_metrics (
  id bigint generated always as identity primary key,
  recorded_date date not null,
  metric_name text not null,
  value numeric,
  unit text,
  raw jsonb,  -- 元のJSON全体をそのまま保持(構造確認・後方互換用)
  created_at timestamptz default now(),
  unique (recorded_date, metric_name)
);

alter table health_metrics enable row level security;

-- anon keyからのINSERT/UPSERTを許可(自宅用途、必要なら後で絞る)
create policy "allow insert for anon"
  on health_metrics for insert
  to anon
  with check (true);

create policy "allow upsert for anon"
  on health_metrics for update
  to anon
  using (true);

create policy "allow select for anon"
  on health_metrics for select
  to anon
  using (true);
```

- `unique (recorded_date, metric_name)` により、同じ日・同じ指標の重複送信は
  `Prefer: resolution=merge-duplicates` ヘッダーでUPSERTされる想定
- 期間が空いても、後から広い日付範囲で再送信すれば穴埋めできる設計

## Health Auto Export側の設定(未実施タスク)

1. 「健康メトリックを選択」で対象指標を選ぶ(歩数、心拍数、睡眠、体重など)
2. URL欄: `https://<プロジェクトID>.supabase.co/rest/v1/health_metrics`
3. ヘッダー:
   - `apikey`: SupabaseのAnon Key
   - `Authorization`: `Bearer <Anon Key>`
   - `Content-Type`: `application/json`
   - `Prefer`: `resolution=merge-duplicates`
4. 送信頻度・トリガーの設定(自動実行のタイミング)
5. 一度試験実行し、Supabase Table Editorでデータが入るか確認
6. 実際に届いたJSON構造を見て、上記テーブル設計(特に`value`/`unit`の抽出方法)を調整

## ダッシュボード(index.html)側のタスク
- Supabaseからselectし、日付×指標でグラフ表示(Chart.js想定)
- 「最終データ日」を表示し、○日以上更新がなければ警告表示
- 既存のギネス家ポータル/Kakeiboと同じSupabaseプロジェクトを想定

## 未解決・要検討事項
- Health Auto ExportのPremium(年額1000円)にするか、Basic買い切り(500円)+手動送信にするか
  → 手動の場合、送信のたびに日付範囲を広めに取り、UPSERTで穴埋めする運用
- 実際のJSON構造確認後、`raw`列からの指標抽出ロジック(トリガー関数 or アプリ側で整形)を決定
