# lolping-ai 配置：~/.config/lolping-ai/config.sh。改完马上生效，不用重启。

# ---- 问号对话框 ----
# 用哪个命令行回答：claude（Claude Code）或 codex
LPA_ASK_AGENT=claude
# codex 用的模型，留空用 codex 自己的默认值（~/.codex/config.toml）
LPA_CODEX_MODEL=''
# 对话框单独的 Claude 登录（运行 lolping-ai login 登录）。没登录时用你平时 claude 的账号。
LPA_CLAUDE_CONFIG_DIR="$HOME/.config/lolping-ai/claude"
# 对话框和桌面版会话的工作目录，“记下来”写到这里的 inbox/
LPA_LOCAL_NOTES_DIR="$HOME/notes"

# ---- 后台动作（推进=记笔记、正在赶来=起草回复、请求协助=解释、需要视野=查代码、危险=记待办）----
# 在哪里跑：local 本机，ssh 远程开发机
LPA_BACKEND=local
# ssh 时的主机，或 ~/.ssh/config 里的别名。需要免密登录，且那台机器上的 claude / codex 已登录。
LPA_HOST=''
# claude 或 codex
LPA_AGENT=claude
# 笔记目录（在跑 agent 的那台机器上，~ 在那台机器上展开）
LPA_NOTES_DIR='~/notes'
# “查代码”的工作目录，改成你的代码仓库
LPA_SEARCH_DIR='~'

# ---- 通用 ----
# 1：带截图；0：只发选中文字和窗口标题
LPA_SCREENSHOT=1
LPA_SHOT_MAX=1600
LPA_TIMEOUT=240
# 额外参数，例如 '--model sonnet'
LPA_CLAUDE_ARGS=''
LPA_CODEX_ARGS=''
