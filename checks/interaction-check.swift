let app = NSApplication.shared
let store = Store()
func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags, _ text: String) -> NSEvent {
    NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)!
}
store.held = true
precondition(!store.handle(key(12,.command,"q")), "松开激活键后必须放行退出快捷键")
precondition(!store.held, "漏掉松键事件后必须恢复状态")
store.enabled = false
_ = store.handle(key(0,.option,"a"))
precondition(store.held, "即使漏掉按下事件也必须识别实际修饰键")
store.editingShortcut = true
store.resetInteraction()
precondition(!store.held && !store.editingShortcut && !store.showing)
store.removeMonitor()
store.removeMonitor()
print("交互检查通过：修饰键恢复、主界面重开状态、重复清理")

let originalSettings = UserDefaults.standard.data(forKey:store.defaultsKey)
defer {
    if let originalSettings { UserDefaults.standard.set(originalSettings,forKey:store.defaultsKey) }
    else { UserDefaults.standard.removeObject(forKey:store.defaultsKey) }
}
store.saved.mode = "切换器"
store.saved.excluded = []
let systemOrder = store.running().map(\.path)
precondition(store.availableApps.map(\.path) == systemOrder, "运行 App 必须保留系统顺序")
store.saved.mode = "自定义"
store.saved.apps = [
    Entry(path:"/System/Library/CoreServices/Finder.app",key:"1"),
    Entry(path:"/Applications/Safari.app",key:"2"),
    Entry(path:"/System/Applications/Messages.app",key:"3"),
    Entry(path:"/System/Applications/Notes.app",key:"4"),
    Entry(path:"/System/Applications/System Settings.app",key:"5")
]
store.saved.modifier = "⌥ Option"
store.saved.delay = 0.01
store.saved.hideAfter = 0
store.saved.silent = []
store.saved.hoverSwitch = false
store.saved.doublePress = false
store.enabled = true
func modifier(_ down: Bool) -> NSEvent {
    let event = CGEvent(keyboardEventSource:nil,virtualKey:58,keyDown:down)!
    event.type = .flagsChanged
    event.flags = down ? .maskAlternate : []
    return NSEvent(cgEvent:event)!
}
for _ in 0..<3 {
    _ = store.handle(modifier(true))
    RunLoop.main.run(until:Date().addingTimeInterval(0.08))
    precondition(store.showing && store.overlay?.isVisible == true, "再次长按必须重新显示浮层")
    precondition(store.overlay?.hidesOnDeactivate == false, "切到其他 App 后浮层仍需可见")
    let session = store.apps
    store.saved.apps.reverse()
    precondition(store.apps == session, "一次长按中的 App 按键映射必须稳定")
    _ = store.handle(modifier(false))
    precondition(!store.showing && !store.held && store.sessionApps == nil, "松开必须结束本轮会话")
}
print("连续触发检查通过：三轮长按、浮层重开、后台显示、会话释放")
if CommandLine.arguments.count > 1 {
    store.present()
    store.selected = 1
    RunLoop.main.run(until:Date().addingTimeInterval(0.2))
    let view = store.overlay!.contentView!
    store.overlay!.displayIfNeeded()
    let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds)!
    view.cacheDisplay(in:view.bounds,to:bitmap)
    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
    print("已保存浮层预览")
}
store.resetInteraction()
