#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GO_DIR="$ROOT_DIR/go_client"
ABI="${1:-arm64-v8a}"
API_LEVEL="${ANDROID_NATIVE_API_LEVEL:-21}"
NDK_DIR="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"

case "$ABI" in
  arm64-v8a) GOARCH="arm64"; CLANG_PREFIX="aarch64-linux-android" ;;
  armeabi-v7a) GOARCH="arm"; CLANG_PREFIX="armv7a-linux-androideabi" ;;
  x86_64) GOARCH="amd64"; CLANG_PREFIX="x86_64-linux-android" ;;
  *) echo "Unsupported ABI: $ABI" >&2; exit 1 ;;
esac

if [[ -z "$NDK_DIR" && -n "${ANDROID_SDK_ROOT:-}" ]]; then
  NDK_DIR="$(find "$ANDROID_SDK_ROOT/ndk" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -V | tail -n1 || true)"
fi
if [[ -z "$NDK_DIR" ]]; then
  echo "NDK not found" >&2
  exit 1
fi

HOST_TAG="linux-x86_64"
if [[ "$(uname -s)" == Darwin* ]]; then HOST_TAG="darwin-x86_64"; fi
TOOLCHAIN_BIN="$NDK_DIR/toolchains/llvm/prebuilt/$HOST_TAG/bin"
CC="$TOOLCHAIN_BIN/${CLANG_PREFIX}${API_LEVEL}-clang"
if [[ ! -x "$CC" ]]; then echo "Compiler not found: $CC" >&2; exit 1; fi

OUT_DIR="$ROOT_DIR/app/src/main/jniLibs/$ABI"
mkdir -p "$OUT_DIR"
(
  cd "$GO_DIR"
  go mod tidy
  GOOS=android GOARCH="$GOARCH" CGO_ENABLED=1 CC="$CC"     go build -trimpath -ldflags=-checklinkname=0 -o "$OUT_DIR/libclient.so" .
)
echo "Built $OUT_DIR/libclient.so"
