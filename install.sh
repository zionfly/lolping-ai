#!/usr/bin/env bash
# Installs lolPing (with AI pings) and lolping-ai on an Apple Silicon Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/zionfly/lolping-ai/main/install.sh | bash
#
# From a clone, ./install.sh does the same with the local files. Options:
#   --agent claude|codex   which CLI the question-mark panel uses (default: asks, or claude)
#   --devbox               also prepare ~/notes on LPA_HOST (for background actions over ssh)
#   --uninstall            remove everything this installed (settings and notes are kept)
set -euo pipefail

REPO=zionfly/lolping-ai
LOLPING_REPO=zionfly/lolPing
LOLPING_TAG=v0.5.1-ai.2
SHARE="$HOME/.local/share/lolping-ai"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/lolping-ai"
SETTINGS="$HOME/Library/Application Support/lolPing/settings.json"

agent='' devbox=0 uninstall=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) agent="${2:-}"; shift 2 ;;
    --devbox) devbox=1; shift ;;
    --uninstall) uninstall=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf 'lolping-ai install: %s\n' "$*" >&2; exit 1; }

if [ "$uninstall" = 1 ]; then
  osascript -e 'quit app "lolPing"' >/dev/null 2>&1 || true
  rm -rf /Applications/lolPing.app "$HOME/Applications/LolpingAsk.app" "$SHARE" "$HOME/.local/bin/lolping-ai"
  say "removed lolPing, LolpingAsk and lolping-ai (kept $CONF_DIR, $SETTINGS and ~/notes)"
  exit 0
fi

[ "$(uname -s)" = Darwin ] || die "macOS only"
[ "$(uname -m)" = arm64 ] || die "needs an Apple Silicon Mac (lolPing's Mac build is arm64 only)"

# Source: this clone, or a fresh download of the repo.
# Piped from curl, BASH_SOURCE is empty: never mistake the current directory for a clone.
HERE=''
[ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ] && HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "$HERE" ] && [ -f "$HERE/bin/lolping-ai" ] && [ -f "$HERE/mac/LolpingAsk.swift" ]; then
  SRC="$HERE"
else
  say "downloading lolping-ai"
  rm -rf "$SHARE.tmp" && mkdir -p "$SHARE.tmp"
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$SHARE.tmp" --strip-components 1
  rm -rf "$SHARE" && mv "$SHARE.tmp" "$SHARE"
  SRC="$SHARE"
fi

# lolPing with AI pings, from the fork's release.
if [ ! -d /Applications/lolPing.app ] || ! grep -q aiPingMap /Applications/lolPing.app/Contents/Resources/app.asar 2>/dev/null; then
  say "installing lolPing ($LOLPING_TAG)"
  tmp="$(mktemp -d)"
  curl -fL --progress-bar -o "$tmp/lolPing.dmg" \
    "https://github.com/$LOLPING_REPO/releases/download/$LOLPING_TAG/lolPing-0.5.1-arm64.dmg"
  mnt="$(hdiutil attach -nobrowse -readonly "$tmp/lolPing.dmg" | awk -F'\t' '/\/Volumes\// {print $NF}' | tail -1)"
  osascript -e 'quit app "lolPing"' >/dev/null 2>&1 || true
  rm -rf /Applications/lolPing.app
  cp -R "$mnt/lolPing.app" /Applications/
  hdiutil detach -quiet "$mnt" || true
  rm -rf "$tmp"
  xattr -dr com.apple.quarantine /Applications/lolPing.app 2>/dev/null || true
else
  say "lolPing with AI pings is already installed"
fi

# The question-mark panel: prebuilt from the release, or built here when Swift is available.
say "installing LolpingAsk (the question-mark panel)"
if command -v swiftc >/dev/null 2>&1; then
  "$SRC/mac/build-ask.sh" >/dev/null
else
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/ask.zip" "https://github.com/$REPO/releases/latest/download/LolpingAsk.zip"
  mkdir -p "$HOME/Applications" && rm -rf "$HOME/Applications/LolpingAsk.app"
  ditto -x -k "$tmp/ask.zip" "$HOME/Applications"
  rm -rf "$tmp"
  xattr -dr com.apple.quarantine "$HOME/Applications/LolpingAsk.app" 2>/dev/null || true
fi

say "linking ~/.local/bin/lolping-ai"
mkdir -p "$HOME/.local/bin" "$CONF_DIR"
ln -sf "$SRC/bin/lolping-ai" "$HOME/.local/bin/lolping-ai"

# Which CLI answers in the panel.
if [ -z "$agent" ]; then
  has_claude=0 has_codex=0
  command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ] && has_claude=1
  [ -x /Applications/Codex.app/Contents/Resources/codex ] || command -v codex >/dev/null 2>&1 && has_codex=1
  agent=claude
  if [ "$has_claude" = 0 ] && [ "$has_codex" = 1 ]; then agent=codex; fi
  if [ "$has_claude" = 1 ] && [ "$has_codex" = 1 ] && [ -r /dev/tty ]; then
    printf '问号对话框用哪个？[1] Claude Code  [2] Codex  (默认 1): '
    read -r ans < /dev/tty || ans=''
    [ "$ans" = 2 ] && agent=codex
  fi
fi
case "$agent" in claude|codex) ;; *) die "--agent must be claude or codex" ;; esac

if [ ! -f "$CONF_DIR/config.sh" ]; then
  sed "s/^LPA_ASK_AGENT=.*/LPA_ASK_AGENT=$agent/" "$SRC/config.example.sh" > "$CONF_DIR/config.sh"
  say "wrote $CONF_DIR/config.sh (panel: $agent)"
else
  sed -i '' "s/^LPA_ASK_AGENT=.*/LPA_ASK_AGENT=$agent/" "$CONF_DIR/config.sh"
  grep -q '^LPA_ASK_AGENT=' "$CONF_DIR/config.sh" || echo "LPA_ASK_AGENT=$agent" >> "$CONF_DIR/config.sh"
  say "kept $CONF_DIR/config.sh (panel: $agent)"
fi

# Turn AI pings on in lolPing's settings, keeping everything else the user set.
say "turning on AI pings in lolPing"
mkdir -p "$(dirname "$SETTINGS")"
osascript -e 'quit app "lolPing"' >/dev/null 2>&1 || true
/usr/bin/osascript -l JavaScript - "$SETTINGS" <<'JXA'
ObjC.import('Foundation');
function run(a) {
  var path = a[0], s = {};
  var raw = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  if (!raw.isNil()) { try { s = JSON.parse(raw.js); } catch (e) { s = {}; } }
  s.aiPings = true;
  // lolPing's own updater would replace this build with upstream, which has no AI pings.
  s.autoUpdateCheck = false;
  $(JSON.stringify(s, null, 2)).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
}
JXA

mkdir -p "$HOME/notes/inbox" "$HOME/notes/attachments"
[ -f "$HOME/notes/CLAUDE.md" ] || cp "$SRC/devbox/CLAUDE.md" "$HOME/notes/CLAUDE.md"
[ -e "$HOME/notes/AGENTS.md" ] || ln -s CLAUDE.md "$HOME/notes/AGENTS.md"

if [ "$devbox" = 1 ]; then
  . "$CONF_DIR/config.sh"
  [ -n "${LPA_HOST:-}" ] || die "set LPA_HOST in $CONF_DIR/config.sh first"
  say "preparing ~/notes on $LPA_HOST"
  ssh -o BatchMode=yes "$LPA_HOST" 'mkdir -p ~/.cache/lolping-ai && cat > ~/.cache/lolping-ai/CLAUDE.md' < "$SRC/devbox/CLAUDE.md"
  ssh -o BatchMode=yes "$LPA_HOST" "bash -s -- \$HOME/notes \$HOME/.cache/lolping-ai/CLAUDE.md" < "$SRC/devbox/setup.sh"
fi

open /Applications/lolPing.app

cat <<EOF

装好了。还差三步：

  1. 权限：系统设置 → 隐私与安全性，给 lolPing 打开
       · 辅助功能（读鼠标键盘，没有它轮盘打不开）
       · 屏幕与系统音频录制（截图，打开后退出再重开 lolPing）
     第一次打开如果提示无法验证开发者：在“隐私与安全性”底部点“仍要打开”。
  2. 登录：问号对话框用 ${agent}，确认它已登录
       · claude：终端里运行 claude，输入 /login；想用另一个账号就运行 lolping-ai login
       · codex：打开 Codex.app 登录，或运行 codex login
  3. 试一下：按住 ⌥ Option 拖动，在轮盘上选“敌人消失”（问号）松手。

检查：lolping-ai doctor     配置：$CONF_DIR/config.sh     卸载：再运行本脚本加 --uninstall
EOF
