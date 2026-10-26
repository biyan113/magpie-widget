#!/bin/bash
# Developer ID 签名、公证、装订，然后替换本机 ~/Applications 里的 Magpie Widget。
# 公证账号先存进钥匙串，脚本不读取密码：
#   xcrun notarytool store-credentials magpie-notary \
#     --apple-id "$APPLE_ID" --team-id "$DEVELOPMENT_TEAM" --password "$APPLE_PASSWORD"
set -euo pipefail
cd "$(dirname "$0")/.."
TEAM="${DEVELOPMENT_TEAM:-534WBL65N6}"
PROFILE="${NOTARY_KEYCHAIN_PROFILE:-magpie-notary}"
APP="build/Build/Products/Release/MagpieWidget.app"
ZIP="build/MagpieWidget.zip"
DEST="${MAGPIE_INSTALL_DIR:-$HOME/Applications/MagpieWidget.app}"

xcodebuild -project MagpieWidget.xcodeproj -scheme MagpieWidget \
  -configuration Release -derivedDataPath build \
  CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ENABLE_HARDENED_RUNTIME=YES \
  build

# xcodebuild 对非 archive 构建会写 --timestamp=none，公证不接受。按从内到外重新签名。
sign_with_timestamp() {
  local target="$1"
  local entitlements
  entitlements="$(mktemp)"
  codesign -d --entitlements :- "$target" >"$entitlements" 2>/dev/null
  codesign --force --sign "Developer ID Application: WEI PAN (${TEAM})" \
    --timestamp --options runtime --entitlements "$entitlements" "$target"
  rm -f "$entitlements"
}
sign_with_timestamp "$APP/Contents/PlugIns/MagpieWidgets.appex"
sign_with_timestamp "$APP"
codesign --verify --deep --strict "$APP"
if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q 'get-task-allow'; then
  echo "拒绝公证：签名里带有 get-task-allow。" >&2
  exit 1
fi

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
mkdir -p site
cp "$ZIP" site/MagpieWidget-1.0.0.zip
bash Scripts/publish-r2.sh

osascript -e 'tell application id "net.bytenote.MagpieWidget" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -f "${DEST}/Contents/MacOS/MagpieWidget" >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST"
ditto "$APP" "$DEST"
open "$DEST"
printf 'Installed %s\nNotarized zip: %s\n' "$DEST" "$PWD/$ZIP"
