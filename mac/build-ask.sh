#!/usr/bin/env bash
# Builds the chat panel the "claude" action opens next to a ping, into ~/Applications/LolpingAsk.app.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/LolpingAsk.app"
BUILD="$(mktemp -d)"
mkdir -p "$BUILD/LolpingAsk.app/Contents/MacOS"
sed -e 's/LolpingAI/LolpingAsk/g' -e 's/com.zionfly.lolping-ai/com.zionfly.lolping-ask/' -e 's/lolPing AI/lolPing Ask/' \
  "$HERE/Info.plist" > "$BUILD/LolpingAsk.app/Contents/Info.plist"
swiftc -O -swift-version 5 -o "$BUILD/LolpingAsk.app/Contents/MacOS/LolpingAsk" "$HERE/LolpingAsk.swift"
mkdir -p "$BUILD/LolpingAsk.app/Contents/Resources"
cp "$HERE/ask.html" "$BUILD/LolpingAsk.app/Contents/Resources/ask.html"
codesign --force --sign - --identifier com.zionfly.lolping-ask "$BUILD/LolpingAsk.app"
mkdir -p "$HOME/Applications"
rm -rf "$APP"; mv "$BUILD/LolpingAsk.app" "$APP"; rm -rf "$BUILD"
echo "installed $APP"
