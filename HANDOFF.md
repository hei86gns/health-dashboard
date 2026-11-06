# HealthDashboard（健康管理ダッシュボード）引き継ぎメモ

## 背景・目的

Apple Healthの健康データ（歩数・心拍数・睡眠など）を自動的に蓄積し、1つのダッシュボードで可視化する個人用アプリ。当初は「iPhoneのHealth Auto ExportアプリからSupabaseへ直接自動送信する」という構想だったが、実際に完成した仕組みは異なる（後述）。

## データの流れ（全体像）

```
iPhone(Health Auto Export)
  └─ 手動で「今すぐ書き出し」→ JSONファイルが ~/Downloads に保存される
       └─ Macのlaunchd(WatchPaths監視)が ~/Downloads の変化を検知
            └─ scripts/upload_export.sh が自動起動
                 ├─ ~/Downloads内のJSONを1つずつ確認
                 │    (.data.metrics が配列かどうかで「それらしいファイル」だけ判定)
                 ├─ Supabaseの ingest_health(RPC関数)へPOST送信
                 ├─ 成功 → inbox/processed/ へ移動、upload.logに記録
                 └─ 失敗 → Downloadsに残す(次回また試行)、macOS通知で失敗を知らせる
```

当初案の「iPhone→Supabase直接送信」は自動化の設定が煩雑だったため断念し、「iPhone側は手動エクスポートのみ・Mac側で自動検知して送信」という折衷案で完成させた。**iPhone側で毎回ボタンを押して書き出す操作は今も必要**（完全自動ではない）。

## データ保存先・テーブル設計

- Supabase プロジェクトB（`zkqvqztadbzqwdwqhyjw`。ギネス家ポータル・Kakeibo_Appと共有）の `health_metrics` テーブル。
- SQLファイルは`01`〜`04`の順に実行され、以下のように設計が進化した:
  - `01_health_metrics.sql`: 最初のテーブル定義＋`ingest_health`関数。当初はanonロールにSELECT/INSERT/UPDATEを全て許可（「自宅用途だから」という理由）。
  - `02_per_user_data.sql`: 家族の他アプリとテーブルを共有する前提で、`user_id`列を追加。**SELECTは`auth.uid() = user_id`のRLSで「自分の行だけ」に制限**。INSERT/UPDATEは自動送信を止めないため**あえてanonのまま許可**（非対称な設計）。
  - `03_fix_ingest_permission.sql`: `ingest_health`が`auth.users`（メール一覧）を参照できず`permission denied`になった不具合を修正。`security invoker`→`security definer`に変更（この関数だけ特別な閲覧権限を持つが、anonロール自体には権限を追加していないので外部から`auth.users`が見えるようにはなっていない）。
  - `04_add_sleep_and_heartrate_ingest.sql`: 睡眠(`sleep_analysis`)と心拍数(`heart_rate`)は他の指標と違い`qty`を持たない特殊構造のため、専用の展開ロジックを追加。
- `ingest_health(data jsonb)`関数は、送られてきたJSONの`data.metrics`配列をループし、指標ごとに以下のいずれかで処理する:
  - **睡眠(`sleep_analysis`)**: 1晩ごとのデータを`sleep_total`/`sleep_core`/`sleep_deep`/`sleep_rem`/`sleep_awake`の5指標に分解して保存。
  - **心拍数(`heart_rate`)**: `Avg`/`Min`/`Max`を`heart_rate`/`heart_rate_min`/`heart_rate_max`の3指標に分解して保存。
  - **それ以外(歩数・安静時心拍数・HRV・歩行系など)**: 汎用ロジックで、単位が加算的なもの(歩数・距離・カロリー等)は日次合計、それ以外(心拍数・割合等)は日次平均。
  - いずれも`(recorded_date, metric_name, user_id)`の一意制約でUPSERT(再送信は上書き)。
- 現在は`heihachiro3@gmail.com`（自分のアカウント）にすべてのデータが紐付く実装。家族の2人目・3人目を追加する場合のひな形（`ingest_health_2`関数、2人目のiPhoneでは送信URLを`.../rpc/ingest_health_2`に変える）が`02_per_user_data.sql`末尾にコメントで用意済み・**未実施**。

## 閲覧側（index.html）

- **認証**: Supabase Auth（メール＋パスワード）でログイン。新規登録UIはなくログイン・パスワードリセットのみ。
- **ログインセッションの分離に注意**: 同じSupabaseプロジェクト・同じGitHub Pagesオリジンをギネス家ポータル/Kakeibo_Appと共有しているため、以前「ログインセッションが混線する」不具合があった。対策として`createClient`に`auth: { storageKey: 'health-dashboard-auth' }`を明示的に指定し、ブラウザの保存領域を他アプリと分離している（他アプリを新設する際もこの対策が必要になる可能性がある）。
- **指標セレクタ＋グラフ**: `health_metrics`から`metric_name`の一覧を取得しプルダウン表示。選択した指標の直近30日分を棒グラフ(Chart.js)で表示。合計・平均も表示。
- **鮮度チップ**: 最終データ日からの経過日数に応じて「最新／◯日更新なし(警告)／◯日更新なし(危険)」を表示。手動エクスポート運用のため、しきい値は緩め（警告4日・危険10日）。
- **「注目ポイント」カード**: 直近7日の平均と、それ以前40日分の平均・標準偏差を比較し、Z値(標準化した差)が閾値(1.5)を超えたら「普段より高め/低め」を表示する個人ベースライン検知機能。対象は歩数・安静時心拍数・HRV・歩行速度・歩行ステップ長・歩行の非対称性/ダブルサポート割合・睡眠時間の8指標。データ点数が足りない指標は計算をスキップする。
- 画面側のクエリは`user_id`で絞り込んでおらず、**RLSに全面的に依存**して「自分の行だけ」が返る前提になっている点は要注意（RLSを誤って緩めると即座に他人のデータも見えてしまう構造）。

## 保存場所・関連ファイル

- フォルダ: `~/Dev/HealthDashboard/`
- 閲覧アプリ本体: `index.html`
- 自動アップロード: `scripts/upload_export.sh`（`.env`からSupabase接続情報を読み込む。値そのものは`.env`にあり、このメモには書かない）
- 自動実行設定: `launchd/com.hei86gns.healthdashboard.uploader.plist`（`~/Downloads`をWatchPathsで監視、ログは`inbox/launchd.out.log`/`launchd.err.log`）
- 処理済みファイル: `inbox/processed/`、処理ログ: `inbox/upload.log`
- DB設計: `sql/01`〜`04`（この順に実行された変更履歴。新しい指標や家族追加の際はこの続きとして`05_`を作るとよい）
- 構想メモ: `docs/plan.md`、動作確認手順: `docs/webhook-test.md`、サンプルデータ: `docs/sample-payload.json`
- Git管理あり、GitHubリポジトリ: `hei86gns/health-dashboard`

## 既知の注意点・今後の候補

1. 家族2人目・3人目の追加は`ingest_health_2`のひな形はあるが未実施。
2. iPhone側の書き出しは手動操作が必要（完全自動化はできていない）。
3. `.env`のSupabase接続情報は`launchd`経由でMacがローカルで読むだけで、GitHubには含まれない（`.gitignore`で除外）。ただし`index.html`側にはブラウザで動かす都合上、SupabaseのURLとanonキーがそのまま埋め込まれている（Supabaseの設計上、anonキーはRLSとセットで保護される前提の公開情報）。

## 機能について質問したいとき

このメモと`index.html`・`sql/`・`scripts/upload_export.sh`があれば、別のフォルダ・別のチャットからでも「新しい指標を追加するには?」「家族の2人目を追加するには?」といった質問にその場で答えられる。会話ログそのものは引き継げないが、このメモが実質的に同じ役割を果たす。
