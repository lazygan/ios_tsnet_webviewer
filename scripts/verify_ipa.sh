#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IPA="$ROOT/build/TailBrowser-unsigned.ipa"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -f "$IPA" ]; then
  echo "ipa not found: $IPA" >&2
  exit 1
fi

unzip -q "$IPA" -d "$WORK"

APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' -print -quit)"
if [ -z "$APP" ]; then
  echo "no .app found in Payload" >&2
  exit 1
fi

PLIST="$APP/Info.plist"
EXE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$PLIST")"

echo "app: $APP"
echo "bundle id: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
echo "minimum OS: $MIN_OS"
echo "ATS web content: $(/usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity:NSAllowsArbitraryLoadsInWebContent' "$PLIST")"
file "$APP/$EXE"

if [ -d "$APP/Frameworks" ]; then
  echo "embedded frameworks:"
  find "$APP/Frameworks" -maxdepth 2 -print
else
  echo "embedded frameworks: none"
fi

if [ "$MIN_OS" != "17.0" ]; then
  echo "warning: expected MinimumOSVersion 17.0, got $MIN_OS" >&2
fi
