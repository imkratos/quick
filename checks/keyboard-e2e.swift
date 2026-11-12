let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.finishLaunching()
let store = Store()
let originalSettings = UserDefaults.standard.data(forKey:store.defaultsKey)
var targets: [NSRunningApplication] = []
let root = URL(fileURLWithPath:CommandLine.arguments[1])
let mode = CommandLine.arguments[2]
let fallback = mode == "fallback"
let focusCheck = mode == "focus"
let packaged = mode == "packaged"
var packagedApp: NSRunningApplication?
var originalPackagedSettings: Data?
let packagedDefaults = UserDefaults(suiteName:"local.craft.glassswitch")!
func wait(_ seconds: TimeInterval = 0.2) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        while let event = app.nextEvent(matching:.any,until:Date(),inMode:.default,dequeue:true) { app.sendEvent(event) }
        RunLoop.main.run(until:min(deadline,Date().addingTimeInterval(0.005)))
    }
}
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { print("FAIL: \(message)"); failures += 1 }
}
var failures = 0
for name in ["A", "B"] {
    let log = root.appendingPathComponent("\(name).log")
    FileManager.default.createFile(atPath:log.path,contents:Data())
    let config = NSWorkspace.OpenConfiguration()
    config.arguments = [log.path] + (focusCheck ? ["--blocker"] : []); config.createsNewApplicationInstance = true
    var done = false
    NSWorkspace.shared.openApplication(at:root.appendingPathComponent("\(name).app"),configuration:config) { target, error in
        if let target { targets.append(target) } else { print("Launch error: \(String(describing:error))") }
        done = true
    }
    let deadline = Date().addingTimeInterval(5)
    while !done && Date() < deadline { wait(0.05) }
    wait()
}
if targets.count != 2 { fatalError("无法启动两个键盘测试应用") }
store.saved.mode = "自定义"
store.saved.apps = [Entry(path:root.appendingPathComponent("A.app").path,key:"1"),Entry(path:root.appendingPathComponent("B.app").path,key:"2")]
store.saved.delay = 0.04; store.saved.hideAfter = 0
store.saved.modifier = "⌥ Option"; store.saved.hideFront = false
store.saved.silent = []; store.saved.doublePress = false; store.saved.hoverSwitch = false
if packaged {
    originalPackagedSettings = packagedDefaults.data(forKey:store.defaultsKey)
    packagedDefaults.set(try! JSONEncoder().encode(store.saved),forKey:store.defaultsKey)
    packagedDefaults.synchronize()
    let config = NSWorkspace.OpenConfiguration()
    var done = false
    NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:CommandLine.arguments[3]),configuration:config) { target, error in
        packagedApp = target; done = true
        if let error { print("正式 App 启动失败：\(error)") }
    }
    let deadline = Date().addingTimeInterval(5)
    while !done && Date() < deadline { wait(0.05) }
    wait(0.4)
    expect(packagedApp != nil,"正式 App 启动成功")
    var taps = [CGEventTapInformation](repeating:CGEventTapInformation(),count:128)
    var count: UInt32 = 0
    _ = CGGetEventTapList(128,&taps,&count)
    let hasTap = taps.prefix(Int(count)).contains { $0.tappingProcess == packagedApp?.processIdentifier && $0.options == .defaultTap }
    print("正式 App 实际模式：\(hasTap ? "全局拦截" : "系统快捷键（无全局拦截权限）")")
} else {
    if fallback { store.installFallbackMonitor() } else { store.installMonitor() }
    if !fallback { expect(store.eventTap != nil,"全局拦截器创建成功") }
}
targets[0].activate(options:[.activateAllWindows]); wait(0.3)
let source = CGEventSource(stateID:.privateState)!
func modifier(_ down: Bool) {
    let event = CGEvent(keyboardEventSource:source,virtualKey:58,keyDown:down)!
    event.type = .flagsChanged; event.flags = down ? .maskAlternate : []
    event.post(tap:.cghidEventTap); wait(0.15)
    if down {
        let deadline = Date().addingTimeInterval(2)
        func visible() -> Bool {
            if !packaged { return store.showing && store.overlay?.isVisible == true }
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] ?? []
            return windows.contains { ($0[kCGWindowOwnerPID as String] as? Int32) == packagedApp?.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == NSWindow.Level.statusBar.rawValue }
        }
        while !visible() && Date() < deadline { wait(0.02) }
        expect(visible(),"长按后浮层实际显示")
        wait(0.05)
    }
}
func key(_ code: CGKeyCode, down: Bool, repeated: Bool = false, modified: Bool = true) {
    let event = CGEvent(keyboardEventSource:source,virtualKey:code,keyDown:down)!
    event.flags = modified ? .maskAlternate : []
    event.setIntegerValueField(.keyboardEventAutorepeat,value:repeated ? 1 : 0)
    event.post(tap:.cghidEventTap); wait(0.08)
}
for (round,target) in [1,0,1].enumerated() {
    modifier(true)
    if !packaged { expect(store.showing,"从目标应用长按可显示浮层") }
    key(target == 0 ? 18 : 19,down:true)
    wait(0.25)
    for _ in 0..<2 { key(target == 0 ? 18 : 19,down:true,repeated:true) }
    key(target == 0 ? 18 : 19,down:false)
    wait(0.25)
    expect(targets[target].isActive,"第 \(round + 1) 轮选择后目标应用激活，第 \(target) 项")
    if focusCheck {
        let element = AXUIElementCreateApplication(targets[target].processIdentifier)
        var focused: CFTypeRef?
        AXUIElementCopyAttributeValue(element,kAXFocusedWindowAttribute as CFString,&focused)
        var title: CFTypeRef?
        if let focused { AXUIElementCopyAttributeValue(focused as! AXUIElement,kAXTitleAttribute as CFString,&title) }
        expect(title as? String == "GlassSwitch 键盘回归检查","主窗口必须获得键盘焦点，实际为 \(String(describing:title))")
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] ?? []
        let front = windows.first { ($0[kCGWindowOwnerPID as String] as? Int32) == targets[target].processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }
        let bounds = front?[kCGWindowBounds as String] as? [String:Any]
        expect(bounds?["Width"] as? Int == 420,"主窗口必须位于同层级的小窗口之前，实际前窗尺寸：\(String(describing:bounds))")
    }
    modifier(false)
    if !packaged { expect(!store.showing && !store.held,"松开后恢复下一轮") }
}
if focusCheck {
    // Minimize the main window and verify switching restores it.
    let element = AXUIElementCreateApplication(targets[0].processIdentifier)
    var main: CFTypeRef?
    AXUIElementCopyAttributeValue(element,kAXMainWindowAttribute as CFString,&main)
    if let main {
        let window = main as! AXUIElement
        AXUIElementSetAttributeValue(window,kAXMinimizedAttribute as CFString,kCFBooleanTrue)
        targets[1].activate(options:[]); wait()
        modifier(true); key(18,down:true); key(18,down:false); modifier(false); wait(0.2)
        var minimized: CFTypeRef?
        AXUIElementCopyAttributeValue(window,kAXMinimizedAttribute as CFString,&minimized)
        expect(minimized as? Bool == false,"切换时必须恢复最小化的主窗口")
    } else { expect(false,"最小化恢复测试需要目标主窗口") }
}
// Check actual global window order, not just the active application's flag.
let finderConfig = NSWorkspace.OpenConfiguration()
var finderOpened = false
NSWorkspace.shared.open([root], withApplicationAt:URL(fileURLWithPath:"/System/Library/CoreServices/Finder.app"), configuration:finderConfig) { _, _ in finderOpened = true }
let finderDeadline = Date().addingTimeInterval(5)
while !finderOpened && Date() < finderDeadline { wait(0.05) }
wait(0.3)
let finder = NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.finder").first!
for target in [0,1] {
    finder.activate(options:[.activateAllWindows]); wait(0.3)
    let before = CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] ?? []
    expect(before.contains { ($0[kCGWindowOwnerPID as String] as? Int32) == finder.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 },"Finder 必须有可见窗口，才能验证遮挡")
    modifier(true)
    key(target == 0 ? 18 : 19,down:true)
    key(target == 0 ? 18 : 19,down:false)
    modifier(false); wait(0.3)
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] ?? []
    let front = windows.first { ($0[kCGWindowLayer as String] as? Int) == 0 && [finder.processIdentifier, targets[target].processIdentifier].contains($0[kCGWindowOwnerPID as String] as? Int32 ?? -1) }
    expect(front?[kCGWindowOwnerPID as String] as? Int32 == targets[target].processIdentifier,"目标窗口必须排在 Finder 前面")
}
// Reuse one held modifier across multiple selections, including after activation.
modifier(true)
for target in [0,1] {
    key(target == 0 ? 18 : 19,down:true)
    key(target == 0 ? 18 : 19,down:false)
    wait(0.2)
    expect(targets[target].isActive,"同次长按可连续切换，第 \(target) 项")
}
modifier(false)
// Releasing the modifier first must not leak repeat or key-up events.
for target in [0,1] {
    modifier(true)
    let code: CGKeyCode = target == 0 ? 18 : 19
    key(code,down:true)
    modifier(false)
    key(code,down:true,repeated:true,modified:false)
    key(code,down:false,modified:false)
    wait(0.2)
    expect(targets[target].isActive,"先松激活键仍可完成切换，第 \(target) 项")
}
modifier(true)
key(48,down:true); key(48,down:false)
key(36,down:true); key(36,down:false)
wait(0.2)
expect(targets[1].isActive,"Tab 选择与回车确认")
modifier(false)
modifier(true)
key(53,down:true); key(53,down:false)
modifier(false)
// After dismissing, ordinary typing must reach the active target.
key(0,down:true,modified:false); key(0,down:false,modified:false)
for name in ["A","B"] {
    let records = try! String(contentsOf:root.appendingPathComponent("\(name).log"),encoding:.utf8)
    expect(!records.split(separator:"\n").contains { line in let fields = line.split(separator:","); return ["18","19","36","48","53"].contains(String(fields[1])) },"\(name) 输入框不能收到选择键、重复按键或松键，日志：\(records)")
}
let bLog = try! String(contentsOf:root.appendingPathComponent("B.log"),encoding:.utf8)
if !bLog.contains(",0,") {
    let aLog = try! String(contentsOf:root.appendingPathComponent("A.log"),encoding:.utf8)
    print("DEBUG ordinary input: A=\(aLog), B=\(bLog), front=\(NSWorkspace.shared.frontmostApplication?.bundleURL?.path ?? "nil"), ownerActive=\(app.isActive), keyWindow=\(String(describing:app.keyWindow)), held=\(store.held), keys=\(store.consumedKeys), refs=\(store.fallbackHotKeys.keys)")
}
expect(bLog.contains(",0,"),"结束切换后普通输入应恢复")
if !packaged { expect(store.consumedKeys.isEmpty && !store.showing,"会话状态必须完全释放") }
store.removeMonitor()
if packaged {
    if let packagedApp {
        packagedApp.terminate()
        let deadline = Date().addingTimeInterval(3)
        while !packagedApp.isTerminated && Date() < deadline { wait(0.05) }
    }
    if let originalPackagedSettings { packagedDefaults.set(originalPackagedSettings,forKey:store.defaultsKey) }
    else { packagedDefaults.removeObject(forKey:store.defaultsKey) }
    packagedDefaults.synchronize()
}
// Close only the Finder window opened for this temporary test directory.
let finderElement = AXUIElementCreateApplication(finder.processIdentifier)
var finderWindows: CFTypeRef?
AXUIElementCopyAttributeValue(finderElement,kAXWindowsAttribute as CFString,&finderWindows)
for window in finderWindows as? [AXUIElement] ?? [] {
    var title: CFTypeRef?
    AXUIElementCopyAttributeValue(window,kAXTitleAttribute as CFString,&title)
    if title as? String == root.lastPathComponent {
        var close: CFTypeRef?
        if AXUIElementCopyAttributeValue(window,kAXCloseButtonAttribute as CFString,&close) == .success, let close {
            AXUIElementPerformAction(close as! AXUIElement,kAXPressAction as CFString)
        }
    }
}
for target in targets { target.terminate() }
if let originalSettings { UserDefaults.standard.set(originalSettings,forKey:store.defaultsKey) }
else { UserDefaults.standard.removeObject(forKey:store.defaultsKey) }
print("\(packaged ? "正式 App" : focusCheck ? "主窗口前置" : fallback ? "系统快捷键" : "全局拦截")跨应用检查：\(failures == 0 ? "通过" : "失败 \(failures) 项")")
exit(failures == 0 ? 0 : 1)
