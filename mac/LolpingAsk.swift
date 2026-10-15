// LolpingAsk: a Claude-style chat panel next to a lolPing ping.
// It shows at once without taking focus, starts `claude` in the background so it is warm by the time the question is
// typed, and picks up the page context that lolping-ai writes into --dir while the panel is already on screen:
//   focus        the selection has been copied; the panel may take the keyboard now
//   meta.json    {"app", "title", "selection"} for the header and chips
//   context.md   the text that goes with the first question
//   shot.jpg / thumb.jpg / url, then done
//   LolpingAsk --x 700 --y 400 --dir ~/.local/state/lolping-ai/ask/123 --cwd ~/notes [--ask "问题"]
import AppKit
import WebKit

let args = CommandLine.arguments
func arg(_ name: String) -> String? {
  guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
  return args[i + 1]
}

let home = NSHomeDirectory()
let pointX = Double(arg("--x") ?? "") ?? 400
let pointY = Double(arg("--y") ?? "") ?? 300
let dir = arg("--dir") ?? "\(home)/.local/state/lolping-ai/ask/manual"
let cwd = arg("--cwd") ?? "\(home)/notes"
let script = arg("--script") ?? "\(home)/.local/bin/lolping-ai"
let claudeConfig = arg("--claude-config") ?? ""
/** claude: one warm `claude -p` process for the whole chat. codex: one `codex exec` per question, resumed by thread id. */
let agent = arg("--agent") == "codex" ? "codex" : "claude"
let codexPath = arg("--codex") ?? "codex"
let codexModel = arg("--codex-model") ?? ""
let fm = FileManager.default

func exists(_ name: String) -> Bool { fm.fileExists(atPath: "\(dir)/\(name)") }
func read(_ name: String) -> String { (try? String(contentsOfFile: "\(dir)/\(name)", encoding: .utf8)) ?? "" }

func envWithPath() -> [String: String] {
  var env = ProcessInfo.processInfo.environment
  env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
  return env
}

/** A JSON literal for passing values into evaluateJavaScript. */
func js(_ v: Any) -> String {
  guard let d = try? JSONSerialization.data(withJSONObject: [v]), let s = String(data: d, encoding: .utf8) else { return "null" }
  return String(s.dropFirst().dropLast())
}

func readMeta() -> [String: Any] {
  (try? JSONSerialization.jsonObject(with: Data(read("meta.json").utf8))) as? [String: Any] ?? [:]
}

final class Panel: NSPanel {
  override var canBecomeKey: Bool { true }
}

/** The header strip left of the buttons: dragging it moves the panel (a web view can't). */
final class DragStrip: NSView {
  override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class Ask: NSObject, WKScriptMessageHandler, NSWindowDelegate {
  let width: CGFloat = 470
  let panel: Panel
  let web: WKWebView
  var top: CGFloat = 0          // the panel grows downward from here
  var screenFrame = NSRect.zero

  var claude: Process?
  var stdin: FileHandle?
  var sessionId: String?
  var lineBuffer = Data()
  var running = false
  var sentContext = false
  var turns: [(q: String, a: String)] = []

  var focused = false, gotDone = false
  var pendingQuestion: String?
  var poll: Timer?

  override init() {
    let config = WKWebViewConfiguration()
    web = WKWebView(frame: NSRect(x: 0, y: 0, width: 470, height: 180), configuration: config)
    panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 180),
                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                  backing: .buffered, defer: false)
    super.init()
    config.userContentController.add(self, name: "app")
    web.setValue(false, forKey: "drawsBackground")
    web.autoresizingMask = [.width, .height]

    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    for b: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] { panel.standardWindowButton(b)?.isHidden = true }
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.backgroundColor = NSColor(name: nil) { a in
      a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.149, green: 0.149, blue: 0.141, alpha: 1) : NSColor(red: 0.98, green: 0.976, blue: 0.96, alpha: 1)
    }
    panel.delegate = self
    panel.contentView?.addSubview(web)
    web.frame = panel.contentView?.bounds ?? .zero
    let strip = DragStrip(frame: NSRect(x: 0, y: 140, width: 470 - 130, height: 40))
    strip.autoresizingMask = [.width, .minYMargin]
    panel.contentView?.addSubview(strip)

    place()
    if let html = Bundle.main.path(forResource: "ask", ofType: "html") {
      let url = URL(fileURLWithPath: html)
      web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
  }

  /** Below-right of the ping, on the ping's screen. pointX/pointY are global points with the origin top-left. */
  func place() {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
    let p = NSPoint(x: pointX, y: primaryHeight - pointY)
    let screen = NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main
    screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    var x = p.x + 40
    if x + width > screenFrame.maxX { x = p.x - width - 40 }
    x = min(max(x, screenFrame.minX + 8), screenFrame.maxX - width - 8)
    top = min(p.y + 20, screenFrame.maxY - 8)
    panel.setFrameOrigin(NSPoint(x: x, y: 0))
    resize(180)
  }

  func resize(_ h: CGFloat) {
    let height = min(max(h, 120), min(620, screenFrame.height - 16))
    var y = top - height
    if y < screenFrame.minY + 8 { y = screenFrame.minY + 8; top = y + height }
    panel.setFrame(NSRect(x: panel.frame.origin.x, y: y, width: panel.frame.width, height: height), display: true)
  }

  var pageReady = false
  var queued: [String] = []

  /** Runs JS in the page, holding it until the page has loaded. */
  func call(_ code: String) {
    guard pageReady else { queued.append(code); return }
    web.evaluateJavaScript(code) { _, err in
      if let e = err as NSError?, e.code != 5 { FileHandle.standardError.write(Data("js: \(e.userInfo)\n".utf8)) }
    }
  }

  // MARK: claude

  /** Started before the question is typed: claude takes seconds to boot, the user takes seconds to type. */
  func startClaude(resume: String? = nil) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    var a = ["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
             "--include-partial-messages", "--allowedTools", "Read,Grep,Glob",
             // No MCP servers: they add seconds to every start and a page question doesn't need them.
             "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}"]
    if let r = resume { a += ["--resume", r] }
    p.arguments = a
    p.currentDirectoryURL = URL(fileURLWithPath: cwd)
    var env = envWithPath()
    // The panel's own login, when it has one; otherwise whatever account `claude` uses.
    if !claudeConfig.isEmpty, fm.fileExists(atPath: "\(claudeConfig)/.claude.json") {
      env["CLAUDE_CONFIG_DIR"] = claudeConfig
      for k in ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL"] { env.removeValue(forKey: k) }
    }
    p.environment = env
    let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
    p.standardInput = inPipe
    p.standardOutput = outPipe
    p.standardError = errPipe
    lineBuffer = Data()
    outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
      let d = h.availableData
      DispatchQueue.main.async { self?.consume(d) }
    }
    p.terminationHandler = { [weak self] proc in
      let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      DispatchQueue.main.async { self?.claudeExited(proc, err) }
    }
    do { try p.run() } catch { return }
    claude = p
    stdin = inPipe.fileHandleForWriting
  }

  func claudeExited(_ proc: Process, _ err: String) {
    guard proc === claude else { return }
    claude = nil
    stdin = nil
    if running {
      running = false
      let msg = err.split(separator: "\n").suffix(2).joined(separator: " ")
      call("app.done(\(js(msg.isEmpty ? "claude 意外退出（\(proc.terminationStatus)）" : msg)))")
    }
  }

  func consume(_ data: Data) {
    lineBuffer.append(data)
    while let nl = lineBuffer.firstIndex(of: 0x0A) {
      let line = lineBuffer.subdata(in: lineBuffer.startIndex..<nl)
      lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
      guard let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
      if let s = o["session_id"] as? String { sessionId = s }
      switch o["type"] as? String {
      case "stream_event":
        guard running, let e = o["event"] as? [String: Any] else { continue }
        if let d = e["delta"] as? [String: Any], d["type"] as? String == "text_delta", let t = d["text"] as? String {
          if !turns.isEmpty { turns[turns.count - 1].a += t }
          call("app.delta(\(js(t)))")
        } else if e["type"] as? String == "content_block_start",
                  let b = e["content_block"] as? [String: Any], b["type"] as? String == "tool_use" {
          call("app.status(\(js("正在用 \(b["name"] as? String ?? "工具")…")))")
        }
      case "result":
        guard running else { continue }
        running = false
        if turns.last?.a.isEmpty ?? false, let r = o["result"] as? String, !r.isEmpty {
          turns[turns.count - 1].a = r
          call("app.delta(\(js(r)))")
        }
        let failed = (o["is_error"] as? Bool) ?? false
        var msg = (o["result"] as? String) ?? "出错了"
        if msg.lowercased().contains("limit") || msg.contains("Not logged in") {
          msg += "\n\n这是 claude 命令行登录的账号的问题，和桌面版无关。在终端运行 lolping-ai login，给对话框登录另一个账号。"
        }
        call("app.done(\(failed ? js(msg) : "null"))")
      default:
        break
      }
    }
  }

  // MARK: codex

  var threadId: String?

  func runCodex(_ text: String, image: String?) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    var a = [codexPath, "exec"]
    if let t = threadId { a += ["resume", t] }
    a += ["--json", "--skip-git-repo-check"]
    // `exec resume` has no --sandbox flag; the config key does the same for both.
    a += ["-c", "sandbox_mode=\"read-only\""]
    if !codexModel.isEmpty { a += ["-m", codexModel] }
    if let img = image { a += ["-i", img] }
    a.append("-")
    p.arguments = a
    p.currentDirectoryURL = URL(fileURLWithPath: cwd)
    p.environment = envWithPath()
    let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
    p.standardInput = inPipe
    p.standardOutput = outPipe
    p.standardError = errPipe
    lineBuffer = Data()
    outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
      let d = h.availableData
      DispatchQueue.main.async { self?.consumeCodex(d) }
    }
    p.terminationHandler = { [weak self] proc in
      let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      DispatchQueue.main.async { self?.claudeExited(proc, err) }
    }
    do { try p.run() } catch {
      running = false
      call("app.done(\(js("启动 codex 失败：\(error.localizedDescription)")))")
      return
    }
    claude = p
    inPipe.fileHandleForWriting.write(Data(text.utf8))
    try? inPipe.fileHandleForWriting.close()
  }

  /** codex exec --json: thread.started, item.* (agent_message carries the answer), turn.completed / turn.failed. */
  func consumeCodex(_ data: Data) {
    lineBuffer.append(data)
    while let nl = lineBuffer.firstIndex(of: 0x0A) {
      let line = lineBuffer.subdata(in: lineBuffer.startIndex..<nl)
      lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
      guard running, let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
      let type = o["type"] as? String ?? ""
      let item = o["item"] as? [String: Any] ?? [:]
      switch type {
      case "thread.started":
        threadId = o["thread_id"] as? String
      case "item.started", "item.updated":
        if let t = item["type"] as? String, t != "agent_message" {
          call("app.status(\(js(t == "reasoning" ? "思考中…" : "正在\(t == "command_execution" ? "运行命令" : "处理")…")))")
        }
      case "item.completed":
        if item["type"] as? String == "agent_message", let t = item["text"] as? String {
          let sep = (turns.last?.a.isEmpty ?? true) ? "" : "\n\n"
          if !turns.isEmpty { turns[turns.count - 1].a += sep + t }
          call("app.delta(\(js(sep + t)))")
        }
      case "turn.completed":
        running = false
        call("app.done(null)")
      case "turn.failed", "error":
        running = false
        var msg = (o["error"] as? [String: Any])?["message"] as? String ?? o["message"] as? String ?? "codex 出错了"
        // The message is often a JSON error body; show its inner message.
        if let d = msg.data(using: .utf8), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
           let inner = (j["error"] as? [String: Any])?["message"] as? String { msg = inner }
        call("app.done(\(js(msg)))")
      default:
        break
      }
    }
  }

  func message(_ text: String, image: String?) -> Data {
    var content: [[String: Any]] = []
    if let path = image, let img = fm.contents(atPath: path) {
      content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": img.base64EncodedString()]])
    }
    content.append(["type": "text", "text": text])
    let msg: [String: Any] = ["type": "user", "message": ["role": "user", "content": content]]
    var data = (try? JSONSerialization.data(withJSONObject: msg)) ?? Data()
    data.append(0x0A)
    return data
  }

  func ask(_ q: String) {
    // The first question waits briefly for the screenshot so it can go along.
    if !sentContext && !gotDone {
      pendingQuestion = q
      call("app.status('正在截取页面…')")
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.flushPending(force: true) }
      return
    }
    var text = q
    var image: String?
    if !sentContext {
      let ctx = read("context.md")
      text = ctx.isEmpty ? q : "\(ctx)\n\n我的问题：\(q)"
      image = exists("shot.jpg") ? "\(dir)/shot.jpg" : nil
      sentContext = true
    }
    running = true
    call("app.status('思考中…')")
    if agent == "codex" {
      runCodex(text, image: image)
    } else {
      if claude == nil { startClaude(resume: sessionId) }
      stdin?.write(message(text, image: image))
    }
  }

  func flushPending(force: Bool) {
    guard let q = pendingQuestion, gotDone || force else { return }
    pendingQuestion = nil
    gotDone = true
    ask(q)
  }

  // MARK: page context from lolping-ai

  func startPolling() {
    poll = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in self?.tick() }
  }

  func tick() {
    if !focused && exists("focus") {
      focused = true
      let meta = readMeta()
      let source = [meta["app"] as? String ?? "", meta["title"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " — ")
      call("app.source(\(js(source.isEmpty ? "当前页面" : source)))")
      call("app.context({loading: true, selection: \((meta["selection"] as? Int) ?? 0)})")
      takeFocus()
    }
    if !gotDone && exists("done") {
      gotDone = true
      showContext()
      flushPending(force: false)
    }
    if focused && gotDone { poll?.invalidate() }
  }

  func showContext() {
    let meta = readMeta()
    var thumb = ""
    if let d = fm.contents(atPath: "\(dir)/thumb.jpg") { thumb = "data:image/jpeg;base64,\(d.base64EncodedString())" }
    let ctx: [String: Any] = [
      "loading": false, "thumb": thumb, "label": "页面截图",
      "selection": (meta["selection"] as? Int) ?? 0, "url": read("url").trimmingCharacters(in: .whitespacesAndNewlines),
      "noScreen": (meta["screen"] as? Bool) == false,
    ]
    call("app.context(\(js(ctx)))")
  }

  func takeFocus() {
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(web)
    call("app.focus()")
  }

  // MARK: actions from the page

  func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
    guard let body = m.body as? [String: Any], let type = body["type"] as? String else { return }
    switch type {
    case "ready":
      pageReady = true
      call("app.agent(\(js(agent)))")
      queued.forEach(call)
      queued = []
      if let q = arg("--ask") { call("document.getElementById('input').value = \(js(q)); send()") }
    case "height":
      if let h = body["h"] as? Double { resize(CGFloat(h)) }
    case "send":
      if let t = body["text"] as? String {
        turns.append((q: t, a: ""))
        ask(t)
      }
    case "stop":
      // Ending the process is the only way to stop a turn; the next question resumes the same session.
      running = false
      claude?.terminate()
      claude = nil
      call("app.done(null)")
    case "copy":
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(body["text"] as? String ?? "", forType: .string)
    case "note":
      saveNote()
    case "openApp":
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/bin/bash")
      p.arguments = [script, "--saved", "claude-app"]
      p.environment = envWithPath()
      try? p.run()
      quit()
    case "screenSettings":
      NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    case "link":
      if let s = body["href"] as? String, let u = URL(string: s) { NSWorkspace.shared.open(u) }
    case "close":
      quit()
    default:
      break
    }
  }

  /** Appends the conversation to today's inbox note, under the page it came from. */
  func saveNote() {
    guard !turns.isEmpty else { return }
    let meta = readMeta()
    let source = [meta["app"] as? String ?? "", meta["title"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " — ")
    let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
    let hm = DateFormatter(); hm.dateFormat = "HH:mm"
    let now = Date()
    let inbox = "\(cwd)/inbox"
    try? fm.createDirectory(atPath: inbox, withIntermediateDirectories: true)
    let path = "\(inbox)/\(day.string(from: now)).md"
    let url = read("url").trimmingCharacters(in: .whitespacesAndNewlines)
    var block = "\n## \(hm.string(from: now)) · \(source)\n\n"
    if !url.isEmpty { block += "来源：\(url)\n\n" }
    block += turns.map { "**问：**\($0.q)\n\n\($0.a)" }.joined(separator: "\n\n") + "\n"
    if let h = FileHandle(forWritingAtPath: path) {
      h.seekToEndOfFile(); h.write(Data(block.utf8)); try? h.close()
    } else {
      try? block.write(toFile: path, atomically: true, encoding: .utf8)
    }
    call("app.toast(\(js("已记到 inbox/\(day.string(from: now)).md")))")
  }

  func quit() {
    claude?.terminate()
    NSApp.terminate(nil)
  }

  func windowWillClose(_ notification: Notification) { quit() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let ask = Ask()
// On screen at once, without taking the keyboard from the app whose selection is still being copied.
ask.panel.orderFrontRegardless()
fm.createFile(atPath: "\(dir)/shown", contents: nil)  // lets lolping-ai and tests see when the panel was up
if agent == "claude" { ask.startClaude() }
ask.startPolling()
app.run()
