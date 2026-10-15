# lolping-ai

把英雄联盟的信号轮盘变成桌面上的 AI 入口：在任意窗口按住 **⌥ Option** 拖动，选一个信号松手，信号照常弹出，然后把那个窗口交给**你自己的** Claude Code 或 Codex。

- **问号（敌人消失）**：信号旁边弹出一个 Claude 风格的对话框，带上那个窗口的截图、选中的文字、标题（浏览器还有网址），你直接提问、追问，“记下来”存进笔记。
- **其他信号**：在后台直接处理——记笔记、起草回复（放进剪贴板）、解释、查代码、记待办。

基于 [lolPing](https://github.com/darrenprx/lolPing)，信号部分来自它的 fork [zionfly/lolPing](https://github.com/zionfly/lolPing/tree/feat/ai-pings)。

## 安装

需要 Apple 芯片的 Mac（M1 及以后），macOS 13+，并且装好以下任一个且已登录：

- [Claude Code](https://docs.claude.com/en/docs/claude-code)（`claude` 命令）
- [Codex](https://openai.com/codex)（Codex.app 或 `codex` 命令）

一条命令：

```bash
curl -fsSL https://raw.githubusercontent.com/zionfly/lolping-ai/main/install.sh | bash
```

它会安装 lolPing（带 AI 信号的版本）、问号对话框 `~/Applications/LolpingAsk.app` 和 `lolping-ai` 命令，并打开 lolPing。两个都装了的话会问你对话框用 Claude 还是 Codex（也可以加 `-s -- --agent codex` 指定）。

装完后：

1. **权限**：系统设置 → 隐私与安全性，给 **lolPing** 打开
   - **辅助功能**：读鼠标和键盘，没有它轮盘打不开
   - **屏幕与系统音频录制**：截图用，打开后退出再重开 lolPing
   - 第一次打开提示“无法验证开发者”：在“隐私与安全性”页面底部点“仍要打开”
2. **登录**：确认 `claude` 或 Codex 已登录。想让对话框用另一个 Claude 账号（不影响你平时的 `claude`），运行 `lolping-ai login`。
3. **试一下**：按住 ⌥ 拖动，选“敌人消失”（问号）松手。

检查状态：`lolping-ai doctor`。卸载：`curl -fsSL …/install.sh | bash -s -- --uninstall`。

## 信号和动作

| 信号 | 做什么 |
| --- | --- |
| 敌人消失（问号） | 弹出对话框，用本机 claude / codex 回答，可以追问、复制、记下来、转到桌面版 |
| 敌方视野 | 打开 Codex 桌面版新会话，上下文已填好 |
| 推进 | 记笔记，追加到 `~/notes/inbox/<日期>.md` |
| 正在赶来 | 起草回复，放进剪贴板（不会发送） |
| 请求协助 | 解释，弹窗显示 |
| 需要视野 | 在 `LPA_SEARCH_DIR` 里查代码 |
| 危险 | 记待办，追加到 `~/notes/todo.md` |

每个信号对应什么动作，在 lolPing 设置 → **AI** 里改（也可以改成“在 Claude 里问”打开 Claude 桌面版）。

## 配置

`~/.config/lolping-ai/config.sh`，说明见 [`config.example.sh`](config.example.sh)。常用的：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `LPA_ASK_AGENT` | `claude` | 问号对话框用 `claude` 还是 `codex` |
| `LPA_CODEX_MODEL` | 空 | codex 的模型，空则用 codex 默认 |
| `LPA_BACKEND` | `local` | 后台动作在本机跑，或 `ssh` 到 `LPA_HOST` |
| `LPA_SEARCH_DIR` | `~` | “查代码”的目录 |

提示词在 [`prompts/`](prompts)，笔记目录里的 `CLAUDE.md`（`AGENTS.md` 是它的软链接）可以写你的背景和回复口吻。

## 它怎么工作

```
⌥ 拖动 → lolPing 放下信号 → lolping-ai --at x,y <动作>
  问号：LolpingAsk 0.2 秒内弹出（不抢焦点），后台启动 claude / codex
        一次 JXA：找信号下面的窗口 → 切到前台 → ⌘C 取选中文字 → 还原剪贴板 → 对话框拿到焦点
        按窗口 ID 截图 → 第一个问题带上截图发出，追问接着同一个会话
  其他：截图 + 选中文字 → claude -p / codex exec（只读）→ 笔记 / 剪贴板 / 弹窗
```

- 对话框里的 agent 是只读的（Read/Grep/Glob，或 codex 的 read-only 沙箱）；“记下来”由对话框自己写文件。
- 截图和文字只发给你自己配置的 claude / codex。

## 隐私

截图、选中的文字、窗口标题和网址只交给你本机（或你配置的 ssh 主机）上的 claude / codex，再由它们发给各自的模型服务。lolPing 本身的网络行为见它的 README。

## 已知问题

- 只支持 Apple 芯片的 Mac。
- lolPing 没有正式签名：每次更新 lolPing 后要在“辅助功能”和“屏幕录制”里删掉再重新加。为此安装时关掉了 lolPing 的自动更新（上游版本没有 AI 信号）。
- 取选中文字会临时占用剪贴板，之后只还原文字内容。

## 从源码构建

```bash
git clone https://github.com/zionfly/lolping-ai && cd lolping-ai && ./install.sh   # 有 swiftc 时会本地编译对话框
```

lolPing 本体：`git clone -b feat/ai-pings https://github.com/zionfly/lolPing`，按它的 README 构建（`npm ci && npm run dist:mac`）。
