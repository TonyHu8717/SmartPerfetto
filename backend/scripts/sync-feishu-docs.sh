#!/usr/bin/env bash
# Sync setup-troubleshooting.md to Feishu Wiki when content changes.
# Uses a hash file to detect changes; runs idempotently.
set -euo pipefail

DOC_DIR="$(cd "$(dirname "$0")/../../docs/getting-started" && pwd)"
MD_FILE="$DOC_DIR/setup-troubleshooting.md"
HASH_FILE="$DOC_DIR/.setup-troubleshooting.feishu-hash"
FEISHU_OBJ_TOKEN="LwZ5d7fyyokbcExMRQwcfmscngb"

if [ ! -f "$MD_FILE" ]; then
  echo "[feishu-sync] Source file not found: $MD_FILE"
  exit 1
fi

CURRENT_HASH=$(md5sum "$MD_FILE" | awk '{print $1}')
STORED_HASH=""
[ -f "$HASH_FILE" ] && STORED_HASH=$(cat "$HASH_FILE")

if [ "$CURRENT_HASH" = "$STORED_HASH" ]; then
  echo "[feishu-sync] No changes detected (hash: ${CURRENT_HASH:0:8})."
  exit 0
fi

echo "[feishu-sync] Change detected: ${STORED_HASH:0:8} → ${CURRENT_HASH:0:8}, syncing to Feishu..."

cd "$DOC_DIR"
if lark-cli docs +update \
  --doc "$FEISHU_OBJ_TOKEN" \
  --mode overwrite \
  --markdown @./setup-troubleshooting.md; then
  echo "$CURRENT_HASH" > "$HASH_FILE"
  echo "[feishu-sync] Sync successful."
else
  echo "[feishu-sync] Sync FAILED — hash not updated, will retry next time."
  exit 1
fi
