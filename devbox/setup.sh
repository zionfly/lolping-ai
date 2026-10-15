#!/usr/bin/env bash
# Prepares the notes directory on the dev box. Safe to run again: existing files are kept.
set -euo pipefail
NOTES="${1:-$HOME/notes}"
TEMPLATE="${2:-}"  # CLAUDE.md to copy in when the notes have none
mkdir -p "$NOTES/inbox" "$HOME/.cache/lolping-ai"
[ -f "$NOTES/CLAUDE.md" ] || [ -z "$TEMPLATE" ] || cp "$TEMPLATE" "$NOTES/CLAUDE.md"
[ -e "$NOTES/AGENTS.md" ] || [ ! -f "$NOTES/CLAUDE.md" ] || ln -s CLAUDE.md "$NOTES/AGENTS.md"
[ -f "$NOTES/todo.md" ] || printf '# 待办\n\n' > "$NOTES/todo.md"
if [ ! -d "$NOTES/.git" ]; then
  git -C "$NOTES" init -q && git -C "$NOTES" add -A && git -C "$NOTES" -c user.name=lolping-ai -c user.email=lolping-ai@localhost commit -qm 'init notes'
fi
export PATH="$HOME/.local/bin:$PATH"
command -v claude >/dev/null && echo "claude: $(claude --version)" || echo 'claude: not installed'
command -v codex >/dev/null && echo "codex: $(codex --version)" || echo 'codex: not installed'
echo "notes: $NOTES"
