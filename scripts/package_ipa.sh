#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/DerivedData/Build/Products/Release-iphoneos/TailWeb.app"
OUT="$ROOT/build/TailBrowser-unsigned.ipa"

if [ ! -d "$APP" ]; then
  echo "app bundle not found: $APP" >&2
  exit 1
fi

rm -rf "$ROOT/build/ipa"
mkdir -p "$ROOT/build/ipa/Payload"
cp -R "$APP" "$ROOT/build/ipa/Payload/"
rm -f "$OUT"

(
  cd "$ROOT/build/ipa"
  /usr/bin/zip -qry "$OUT" Payload
)

shasum -a 256 "$OUT"
