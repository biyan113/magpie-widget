#!/bin/bash
# 把 site/ 发布到 Cloudflare R2 桶 magpie-widget，公开地址 https://magpie-widget.bytenote.net
# 依赖已登录的 cf CLI。压缩包由 Scripts/release.sh 生成。
set -euo pipefail
cd "$(dirname "$0")/.."
BUCKET="${R2_BUCKET:-magpie-widget}"
SITE="${SITE_DIR:-site}"
ZIP_NAME="${ZIP_NAME:-MagpieWidget-1.0.0.zip}"

put() {
  local key="$1" file="$2" type="$3"
  local bytes
  bytes="$(stat -f %z "$file")"
  cf r2 objects put "$key" --bucket-name "$BUCKET" --file "$file" --content-type "$type" --content-length "$bytes"
}

put index.html "$SITE/index.html" "text/html; charset=utf-8"
put assets/widget-small.png "$SITE/assets/widget-small.png" "image/png"
put assets/gateway.png "$SITE/assets/gateway.png" "image/png"
put "$ZIP_NAME" "$SITE/$ZIP_NAME" "application/zip"
printf 'Published https://magpie-widget.bytenote.net/\n'
