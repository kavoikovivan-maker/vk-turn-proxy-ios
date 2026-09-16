#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen is required"; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo "xcrun is required; run this on macOS"; exit 1; }

if [ ! -d "WireGuardBridge/build/WireGuardTURN.xcframework" ]; then
  make -C WireGuardBridge xcframework
fi

xcodegen generate --spec VKTurnProxy/project.yml --project VKTurnProxy
xcodebuild \
  -project VKTurnProxy/VKTurnProxy.xcodeproj \
  -scheme VKTurnProxy \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
