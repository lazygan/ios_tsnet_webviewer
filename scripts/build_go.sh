#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/ios/Frameworks"
OUT="$OUT_DIR/Tailbridge.xcframework"

if ! command -v gomobile >/dev/null 2>&1; then
  echo "gomobile not found in PATH; install it with 'go install golang.org/x/mobile/cmd/gomobile@<pinned>'" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -rf "$OUT"

cd "$ROOT/go"
gomobile bind -target=ios -o "$OUT" -ldflags="-s -w" ./tailbridge

echo "built: $OUT"
find "$OUT" -maxdepth 5 -type f -name Tailbridge -exec file {} \;
