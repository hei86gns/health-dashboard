#!/bin/bash
# ~/Downloads を見て、Health Auto Exportの手動エクスポート(JSON)らしきファイルを
# 見つけたら Supabase の ingest_health に送信し、inbox/processed/ へ移動する。
# launchd(WatchPaths)から自動実行される想定。手動で実行しても安全(冪等)。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DOWNLOADS_DIR="$HOME/Downloads"
PROCESSED_DIR="$REPO_DIR/inbox/processed"
LOG_FILE="$REPO_DIR/inbox/upload.log"

mkdir -p "$PROCESSED_DIR"
source "$REPO_DIR/.env"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

notify() {
  osascript -e "display notification \"$1\" with title \"HealthDashboard\"" >/dev/null 2>&1 || true
}

shopt -s nullglob
for f in "$DOWNLOADS_DIR"/*.json; do
  # Health Auto Exportの出力らしいJSON(.data.metrics が配列)かどうかを検証。
  # 違う形のJSONは無視して、他のダウンロードファイルに影響しない。
  if ! jq -e '.data.metrics | type == "array"' "$f" >/dev/null 2>&1; then
    continue
  fi

  name="$(basename "$f")"
  http_code=$(curl -s -o /tmp/health_upload_response.json -w '%{http_code}' \
    -X POST "$SUPABASE_URL/rest/v1/rpc/ingest_health" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
    -H "Content-Type: application/json" \
    --data-binary "@$f")

  if [ "$http_code" = "200" ]; then
    rows=$(jq -r '.rows // "?"' /tmp/health_upload_response.json 2>/dev/null || echo "?")
    ts="$(date '+%Y%m%d-%H%M%S')"
    mv "$f" "$PROCESSED_DIR/${ts}-${name}"
    log "OK  ${name} -> ${rows}行 取り込み成功"
  else
    body=$(cat /tmp/health_upload_response.json 2>/dev/null || echo "")
    log "NG  ${name} HTTP ${http_code}: ${body}"
    notify "健康データの取り込みに失敗しました(${name})。ログを確認してください。"
  fi
done
