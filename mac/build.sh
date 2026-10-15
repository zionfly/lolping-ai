#!/usr/bin/env bash
# Builds LolpingAI.app into ~/Applications and starts it at login through a LaunchAgent.
#   mac/build.sh            build, install and (re)start
#   mac/build.sh --uninstall
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/LolpingAI.app"
LABEL=com.zionfly.lolping-ai
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ "${1:-}" = --uninstall ]; then
  rm -rf "$APP" "$AGENT"; echo "removed $APP and $AGENT"; exit 0
fi

BUILD="$(mktemp -d)"
mkdir -p "$BUILD/LolpingAI.app/Contents/MacOS"
cp "$HERE/Info.plist" "$BUILD/LolpingAI.app/Contents/Info.plist"
swiftc -O -swift-version 5 -o "$BUILD/LolpingAI.app/Contents/MacOS/LolpingAI" "$HERE/LolpingAI.swift"
# Ad-hoc signature: macOS ties the Accessibility / Screen Recording grants to it, so a rebuild needs them again.
codesign --force --sign - --identifier "$LABEL" "$BUILD/LolpingAI.app"

mkdir -p "$HOME/Applications"
rm -rf "$APP"; mv "$BUILD/LolpingAI.app" "$APP"; rm -rf "$BUILD"
echo "installed $APP"

mkdir -p "$(dirname "$AGENT")"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/LolpingAI</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo "started $LABEL (runs at login)"
