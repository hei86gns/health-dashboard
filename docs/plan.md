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

## 2026/07/25 ダッシュボード(index.html)作成・Kakeibo型で公開へ

「マイアプリ台帳」Artifactで家の全アプリ構成を棚卸しした結果、Kakeibo_Appが
「Supabaseプロジェクトはポータルと共有しつつ、ログインとコードは独立」の先例
だと判明したため、この構成をそのまま踏襲することに決定。

- **ログイン**: ポータルの家族合言葉方式ではなく、Kakeiboと同じメール+パスワード
  (Supabase標準認証)。セルフ登録フォームは作らず、Supabase Dashboardの
  Authentication → Users → Add user で本人のアカウントを1つ手動作成する運用
- **見た目**: Kakeiboではなくギネス家ポータルのCSS変数・カードUIをそのまま流用
  (`--brand:#1a5c4a` 等)。同じ家族エコシステムの一員として統一感を出す
- **アクセス制限**: `sql/02_restrict_select_to_authenticated.sql` でSELECTを
  authenticatedロール限定に変更。INSERT/UPDATEはanonのまま(iPhoneからの自動送信を止めないため)。
  台帳にも記載されていた「health_metricsがanonキーで読み書き可能なまま」という
  既知の課題をここで解消
- **GitHub/公開**: Kakeiboと同じくポータルとは別の専用リポジトリを新規作成し、
  Publicのまま無料でGitHub Pages公開(非公開リポジトリでのPagesは有料プランが必要なため)。
  鍵(Anon Key)はコードに埋め込むが、公開されて良い前提のもの。実データの保護はRLS+ログインで担保
- 構成: index.html(単一ファイル、Chart.js CDN)。最終データ日から2日で警告・5日で危険表示

## 2026/07/19 夜: パイプライン開通 ✅

iPhoneのHealth Auto Exportから本番URL(RPC)への送信に成功し、7日分がUPSERTされた。
- ハマりどころ1: エクスポート履歴の「応答」欄は空になることがあり当てにならない。
  真のエラーは設定最下部の「アクティビティログを表示」で確認する
- ハマりどころ2: URL欄にペースト時の**末尾スペース**が混入し、全送信が404になっていた
  (エラー中の `%20` が証拠)。ペースト後は末尾にカーソルを置いて⌫で掃除する
- 残タスク: 試用期限2026/07/26までにPremium(年額)かBasic(買い切り+手動)を決める

## 2026/07/19 JSON構造確認済み・設計確定

webhook.site への試験送信で実構造を確認した(サンプル: `docs/sample-payload.json`)。

```json
{ "data": { "metrics": [
    { "name": "step_count", "units": "count",
      "data": [ { "date": "2026-07-13 01:12:00 +0900", "qty": 12.73, "source": "..." } ] }
] } }
```

判明したこと・決定事項:
- **入れ子構造のためテーブル直POSTは不可**(PostgRESTは列名一致のフラットJSONのみ受付)
  → 受け口として **RPC関数 `ingest_health(data jsonb)`** を採用(`sql/01_health_metrics.sql`)
  - 送信先URL: `https://<プロジェクトID>.supabase.co/rest/v1/rpc/ingest_health`
  - 関数内で日次に集計してUPSERTするため `Prefer: resolution=merge-duplicates` ヘッダーは**不要**
  - 必要ヘッダーは `apikey` / `Authorization: Bearer <Anon Key>` / `Content-Type: application/json` の3つ
- **デフォルトでは1分刻みのデータが送られる**(7日分で約2,000点)
  → アプリ側の集計間隔を「日」に変更するのを推奨(関数側でも日次集計するため必須ではない)
- 集計ルール: 加算が意味を持つ単位(count, km, kcal等)は日次合計、それ以外(心拍数等)は日次平均
- 日付は文字列先頭10文字から取得(timestamptz経由だとUTC換算で日付がずれるため)
