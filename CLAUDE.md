# HealthDashboard

作業を始める前に、必ず `HANDOFF.md` を読んでから対応してください。データの流れ(iPhone手動エクスポート→Downloads→launchd監視→アップロードスクリプト→Supabase RPC→テーブル)、DB設計の変遷(sql/01〜04)、認証とRLSの非対称設計(SELECTは本人のみ・INSERTはanon許可)がまとまっています。

機能や仕様についての質問には、`HANDOFF.md`に加えて実際のソース(`index.html`・`sql/`・`scripts/upload_export.sh`)の中身も確認した上で答えてください。

大きな変更（DB設計、launchd設定、RLSポリシーの変更など）を行った場合は、`HANDOFF.md`も合わせて更新してください。`.env`の中身や実際のAPIキーの値は、いかなる場合もHANDOFF.mdやCLAUDE.mdに書かないでください。
