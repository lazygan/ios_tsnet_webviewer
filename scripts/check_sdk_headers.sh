#!/usr/bin/env bash
set -uo pipefail

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "SDK: $SDK"
echo

echo "== WebKit headers: proxyConfigurations =="
grep -R "proxyConfigurations" "$SDK/System/Library/Frameworks/WebKit.framework/Headers" 2>/dev/null \
  || echo "(not found in WebKit headers)"

echo
echo "== Network.framework Swift interfaces: ProxyConfiguration =="
found=0
while IFS= read -r file; do
  if grep -q "ProxyConfiguration" "$file" 2>/dev/null; then
    found=1
    echo "--- $file"
    grep -n "class ProxyConfiguration\|socksv5Proxy\|httpCONNECTProxy\|allowFailover\|applyCredential" "$file" | head -n 40
  fi
done < <(find "$SDK/System/Library/Frameworks/Network.framework" -name '*.swiftinterface' -print 2>/dev/null)

if [ "$found" -eq 0 ]; then
  echo "(no matching swiftinterface found)"
fi
