#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required but not installed. Install it before running this script."
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required but not installed. This script is meant to run on macOS GitHub runners."
  exit 1
fi

if [ ! -d "WireGuardBridge/build/WireGuardTURN.xcframework" ]; then
  echo "==> Building WireGuardBridge xcframework"
  make -C WireGuardBridge xcframework
fi

echo "==> Generating Xcode project from project.yml"
xcodegen generate

echo "==> Listing Xcode targets"
xcodebuild -list -project VKTurnProxy.xcodeproj

echo "==> Building app without code signing"
xcodebuild \
  -project VKTurnProxy.xcodeproj \
  -scheme VKTurnProxy \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

printf '\n==> Build completed successfully.\n'
