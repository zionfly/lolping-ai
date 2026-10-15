// LolpingAI: a menu bar app that owns the global hotkeys and calls bin/lolping-ai.
// ⌥Space pops the action menu at the pointer; ⌃⌥N/R/E/S/T run one action directly; ⌃⌥. stops.
import AppKit
import Carbon.HIToolbox

let home = NSHomeDirectory()
let script = ProcessInfo.processInfo.environment["LPA_SCRIPT"] ?? "\(home)/.local/bin/lolping-ai"

struct Action {
  let id: String
  let title: String
  /** Letter for the ⌃⌥ hotkey and the menu's key equivalent. */
  let key: String
  let keyCode: Int
}

let actions = [
  Action(id: "note", title: "📝 记笔记", key: "n", keyCode: kVK_ANSI_N),
  Action(id: "reply", title: "💬 起草回复", key: "r", keyCode: kVK_ANSI_R),
  Action(id: "explain", title: "❓ 解释", key: "e", keyCode: kVK_ANSI_E),
  Action(id: "search", title: "🔍 查代码", key: "s", keyCode: kVK_ANSI_S),
  Action(id: "todo", title: "✅ 记待办", key: "t", keyCode: kVK_ANSI_T),
]

let logURL = URL(fileURLWithPath: "\(home)/.local/state/lolping-ai/app.log")

/** Appends to app.log; the script's stderr goes there too, so failures are visible without a terminal. */
func appLog(_ line: String) {
  let stamp = ISO8601DateFormatter().string(from: Date())
  guard let data = "\(stamp) \(line)\n".data(using: .utf8) else { return }
  try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  if let h = try? FileHandle(forWritingTo: logURL) {
    h.seekToEndOfFile(); h.write(data); try? h.close()
  } else {
    try? data.write(to: logURL)
  }
}

@discardableResult
func runScript(_ args: [String], wait: Bool) -> Int32 {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/bin/bash")
  p.arguments = [script] + args
  var env = ProcessInfo.processInfo.environment
  env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  p.environment = env
  if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); p.standardError = h }
  appLog("run \(args.joined(separator: " "))")
  do { try p.run() } catch {
    appLog("cannot run \(script): \(error)")
    return -1
  }
  if !wait { return 0 }
  p.waitUntilExit()
  if p.terminationStatus != 0 { appLog("exit \(p.terminationStatus): \(args.joined(separator: " "))") }
  return p.terminationStatus
}

// The script's simulated ⌘C would become ⌥⌘C while the hotkey's modifiers are still down.
func waitForModifiersUp() {
  let deadline = Date().addingTimeInterval(1.5)
  let held: NSEvent.ModifierFlags = [.option, .control, .shift, .command]
  while !NSEvent.modifierFlags.intersection(held).isEmpty && Date() < deadline {
    usleep(20_000)
  }
}

final class Controller: NSObject {
  let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  var busy = false

  func start() {
    status.button?.title = "🎯"
    status.button?.toolTip = "lolPing AI：⌥Space 弹出菜单"
    let m = NSMenu()
    for a in actions {
      let it = NSMenuItem(title: a.title, action: #selector(statusPick(_:)), keyEquivalent: a.key)
      it.keyEquivalentModifierMask = [.control, .option]
      it.representedObject = a.id
      it.target = self
      m.addItem(it)
    }
    m.addItem(.separator())
    addItem(m, "⏹ 停止", #selector(stop), ".")
    addItem(m, "打开上次结果", #selector(openLast), "")
    addItem(m, "打开配置", #selector(openConfig), "")
    m.addItem(.separator())
    addItem(m, "退出 lolPing AI", #selector(quit), "")
    status.menu = m
  }

  func addItem(_ m: NSMenu, _ title: String, _ sel: Selector, _ key: String) {
    let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
    it.keyEquivalentModifierMask = [.control, .option]
    it.target = self
    m.addItem(it)
  }

  /** ⌥Space: capture while the user's app is still in front, then show the menu at the pointer. */
  func popMenu() {
    if busy { return }
    busy = true
    let prev = NSWorkspace.shared.frontmostApplication
    status.button?.title = "⏳"
    DispatchQueue.global(qos: .userInitiated).async {
      waitForModifiersUp()
      let ok = runScript(["capture"], wait: true) == 0
      DispatchQueue.main.async {
        self.status.button?.title = "🎯"
        self.busy = false
        guard ok else { return }
        let m = NSMenu()
        for a in actions {
          let it = NSMenuItem(title: a.title, action: #selector(self.menuPick(_:)), keyEquivalent: a.key)
          it.keyEquivalentModifierMask = []
          it.representedObject = a.id
          it.target = self
          m.addItem(it)
        }
        NSApp.activate(ignoringOtherApps: true)
        m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        // Give focus back so a reply draft can be pasted straight away.
        prev?.activate()
      }
    }
  }

  /** ⌃⌥<letter>: capture and run in one go, no menu. */
  func runDirect(_ id: String) {
    DispatchQueue.global(qos: .userInitiated).async {
      waitForModifiersUp()
      runScript([id], wait: false)
    }
  }

  @objc func menuPick(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    runScript(["--saved", id], wait: false)
  }

  // Clicking the menu bar icon leaves the user's app in front, so capturing after the click still works.
  @objc func statusPick(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.runDirect(id) }
  }

  @objc func stop() { runScript(["stop"], wait: false) }
  @objc func openLast() { runScript(["last"], wait: false) }
  @objc func openConfig() {
    NSWorkspace.shared.open(URL(fileURLWithPath: "\(home)/.config/lolping-ai/config.sh"))
  }
  @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - Global hotkeys (Carbon: no Accessibility permission needed for these)

var hotkeyHandlers: [UInt32: () -> Void] = [:]

func registerHotkey(_ id: UInt32, keyCode: Int, mods: Int, _ f: @escaping () -> Void) {
  hotkeyHandlers[id] = f
  var ref: EventHotKeyRef?
  let hkID = EventHotKeyID(signature: OSType(0x4C50_4149), id: id)  // 'LPAI'
  let err = RegisterEventHotKey(UInt32(keyCode), UInt32(mods), hkID, GetApplicationEventTarget(), 0, &ref)
  if err != noErr { appLog("hotkey \(id) is taken (\(err))") }
}

func installHotkeyHandler() {
  var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
  InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
    var hk = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    let id = hk.id
    DispatchQueue.main.async { appLog("hotkey \(id)"); hotkeyHandlers[id]?() }
    return noErr
  }, 1, &spec, nil, nil)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
controller.start()
installHotkeyHandler()
registerHotkey(1, keyCode: kVK_Space, mods: optionKey) { controller.popMenu() }
for (i, a) in actions.enumerated() {
  registerHotkey(UInt32(10 + i), keyCode: a.keyCode, mods: controlKey | optionKey) { controller.runDirect(a.id) }
}
registerHotkey(2, keyCode: kVK_ANSI_Period, mods: controlKey | optionKey) { controller.stop() }
appLog("started, script \(script)")
app.run()
