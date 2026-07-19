# webhook.site でJSON構造を確認する手順

Health Auto Export が実際にどんなJSONを送るのかを、無料サービス「webhook.site」で確認します。
webhook.site は「届いたデータをそのまま画面に表示してくれる、テスト用の受け皿」です。

```
iPhone (Health Auto Export)
  └─ 試験送信 ──POST──> webhook.site(一時URL)
                            └─ 届いたJSONを画面で確認 ← これが目的
```

## 手順(所要 5〜10分)

### 1. webhook.site で一時URLを取得(Mac or iPhoneのブラウザ)

1. https://webhook.site を開く
2. 開いた瞬間に「Your unique URL」として `https://webhook.site/xxxxxxxx-....` という
   専用URLが発行される
3. そのURLをコピーする(iPhoneに送るには AirDrop やメモ共有が便利)

> ⚠️ このURLは誰でも見られる一時的なテスト用です。健康データが一時的に
> 第三者サービスに送られる点は理解した上で、確認が済んだら使い捨ててください。

### 2. Health Auto Export で試験送信(iPhone)

1. 作成途中のオートメーション(自動化の種類: REST API)を開く
2. **URL欄**に、コピーした webhook.site のURLを貼り付ける
3. ヘッダーは**空のままでOK**(webhook.site は何でも受け取る)
4. エクスポート形式: JSON、バージョン: v2 のままにする
5. 「健康メトリックを選択」で、まずは**歩数など1〜2個だけ**選ぶ(構造確認が目的なので少なくてよい)
6. 手動で1回実行(「今すぐ実行」や「テスト」ボタン)

### 3. 届いたJSONを確認・コピー(ブラウザ)

1. webhook.site のタブに戻ると、左側にリクエストが1件増えている
2. クリックして「Raw Content」(生データ)を表示
3. **JSON全文をコピーして、そのままClaudeのチャットに貼り付ける**

## その後(Claude側で行うこと)

- 貼ってもらったJSONを `docs/sample-payload.json` に保存
- 構造を分析して、Supabaseのテーブル+受け口(RPC関数など)のSQLを確定
- 確認が済んだら、Health Auto Export のURL欄は Supabase のURLに差し替える
