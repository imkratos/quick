import AppKit

// A disposable application with a real text field to detect leaked keystrokes.
final class TargetDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var monitor: Any?
    var blocker: NSPanel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect:NSRect(x:160,y:180,width:420,height:160),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title = "GlassSwitch 键盘回归检查"
        let field = NSTextField(frame:NSRect(x:24,y:60,width:372,height:30))
        field.placeholderString = "检查切换按键是否泄漏"
        window.contentView!.addSubview(field)
        monitor = NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp]) { event in
            let record = "\(event.type.rawValue),\(event.keyCode),\(event.isARepeat)\n"
            let url = URL(fileURLWithPath:CommandLine.arguments[1])
            let handle = try! FileHandle(forWritingTo:url)
            handle.seekToEndOfFile(); handle.write(record.data(using:.utf8)!); try! handle.close()
            return event
        }
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(field)
        NSApp.activate(ignoringOtherApps:true)
        if CommandLine.arguments.contains("--blocker") {
            let panel = NSPanel(contentRect:NSRect(x:200,y:230,width:230,height:90),styleMask:[.titled,.utilityWindow],backing:.buffered,defer:false)
            panel.title = "遮挡小窗"; panel.level = .normal; panel.hidesOnDeactivate = false
            panel.makeKeyAndOrderFront(nil)
            blocker = panel
        }
    }
}
let app = NSApplication.shared
let delegate = TargetDelegate()
app.delegate = delegate
app.run()
