#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your ten-character Apple Team ID}"
xcodebuild -project MagpieWidget.xcodeproj -scheme MagpieWidget \
  -configuration Debug -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Development' \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" build
printf '\nBuilt: %s/build/Build/Products/Debug/MagpieWidget.app\n' "$PWD"
