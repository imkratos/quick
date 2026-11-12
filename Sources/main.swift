import SwiftUI
import Sparkle
import Combine
import AppKit
import Carbon
import ServiceManagement
import UniformTypeIdentifiers

enum AppArtwork {
    static let statusIcon: NSImage = {
        let image = NSImage(size:NSSize(width:18,height:18),flipped:false) { _ in
            NSColor.black.setStroke()
            let ring = NSBezierPath(ovalIn:NSRect(x:2.5,y:3.5,width:12,height:12))
            ring.lineWidth = 2.2
            ring.stroke()
            let tail = NSBezierPath()
            tail.move(to:NSPoint(x:10,y:7))
            tail.line(to:NSPoint(x:15.5,y:1.5))
            tail.lineWidth = 2.6
            tail.lineCapStyle = .round
            tail.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "quick"
        return image
    }()
    static let icon: NSImage = {
        if let url = Bundle.main.url(forResource:"AppIcon",withExtension:"icns"),
           let image = NSImage(contentsOf:url) { return image }
        return NSImage(systemSymbolName:"q.square.fill",accessibilityDescription:"quick")!
    }()
}

struct Entry: Codable, Identifiable, Equatable {
    var id: String { path }
    var path: String
    var key: String
    var name: String { FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "") }
}
struct Profile: Codable, Identifiable { var id = UUID(); var name: String; var apps: [Entry] }
enum GlassTransparency: String, Codable, CaseIterable {
    case low = "低", medium = "中", high = "高"
}
struct Saved: Codable {
    var language: AppLanguage?
    var glassTransparency: GlassTransparency?

    var mode = "Dock"; var apps: [Entry] = []; var silent: [Entry] = []; var excluded: [Entry] = []
    var profiles: [Profile] = []; var delay = Mechanics.activationDelay; var hideAfter = Mechanics.autoHide; var size = Mechanics.overlaySize; var opacity = Mechanics.overlayOpacity
    var hideFront = true; var finderFirst = true; var hoverSwitch = false; var doublePress = false
    var modifier = "⌥ Option"; var characters = "数字和字母"; var keyboard = "全键盘"; var position = "中部"
    var disableSilentKeys = true; var activeScreen = true; var border = 1.0; var x = 0.5; var y = 0.5
    var count = 0; var counts: [String:Int] = [:]; var showStatus = true
}
final class Store: ObservableObject {
    @Published var saved: Saved { didSet { persist() } }
    @Published var page = "配置"; @Published var enabled = true; @Published var selected = 0; @Published var showing = false
    @Published var editingShortcut = false
    @Published var globalShortcutsAvailable = false
    @Published var loginItemStatus = SMAppService.mainApp.status
    @Published var message = ""; @Published var revision = 0
    var overlay: NSPanel?; var timer: Timer?; var hideTimer: Timer?; var held = false; var doublePressWindow = DoublePressWindow()
    var global: Any?; var local: Any?; var eventTap: CFMachPort?; var eventSource: CFRunLoopSource?; var monitorRetry: Timer?
    let defaultsKey = "GlassSwitch.settings.v1"
    init() {
        if let d = UserDefaults.standard.data(forKey: defaultsKey), let value = try? JSONDecoder().decode(Saved.self, from: d) { saved = value } else { saved = Saved() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                guard let self else { return }
                self.revision += 1
                if self.pendingFocus == app.processIdentifier && app.isActive {
                    self.pendingFocus = nil
                    self.raiseMainWindow(of:app)
                }
            }
        }
    }
    var language: AppLanguage { saved.language ?? .simplifiedChinese }
    func text(_ key: String, _ arguments: String...) -> String {
        let template = language.text(key)
        return arguments.isEmpty ? template : String(format:template,locale:language.locale,arguments:arguments)
    }
    var sessionApps: [Entry]?
    var pendingFocus: pid_t?
    var activationRequest = 0
    var consumedKeys: Set<UInt16> = []
    var fallbackHandler: EventHandlerRef?
    var fallbackHotKeys: [UInt16: EventHotKeyRef] = [:]
    var fallbackCharacters: [UInt16: String] = [:]
    func persist() { if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: defaultsKey) } }
    func refreshLoginItemStatus() { loginItemStatus = SMAppService.mainApp.status }
    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled && service.status != .requiresApproval { try service.register() }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
            refreshLoginItemStatus()
            if enabled && loginItemStatus == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            } else if enabled && loginItemStatus != .enabled {
                message = text("未能启用登录时启动，请确认 quick 位于“应用程序”文件夹中，然后重试。")
            }
        } catch {
            refreshLoginItemStatus()
            message = text(enabled ? "无法启用登录时启动：%@" : "无法关闭登录时启动：%@",error.localizedDescription)
        }
    }
    var keys: [String] {
        let base = saved.characters == "仅字母" ? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" : saved.characters == "仅数字" ? "1234567890" : "1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        return Array((saved.keyboard == "左手区域" ? "12345QWERTASDFGZXCVB" : saved.keyboard == "右手区域" ? "67890YUIOPHJKLNM" : base)).map(String.init).filter { base.contains($0) }
    }
    func running() -> [Entry] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }.compactMap { a in a.bundleURL.map { Entry(path: $0.path, key: "") } }
    }
    func dock() -> [Entry] {
        let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")
        var list = (domain?["persistent-apps"] as? [[String:Any]] ?? []).compactMap { item -> Entry? in
            guard let tile = item["tile-data"] as? [String:Any], let file = tile["file-data"] as? [String:Any], let url = file["_CFURLString"] as? String, let path = URL(string: url)?.path else { return nil }
            return Entry(path: path, key: "")
        }
        if saved.finderFirst { list.insert(Entry(path: "/System/Library/CoreServices/Finder.app", key: ""), at: 0) }
        return list
    }
    var apps: [Entry] { sessionApps ?? availableApps }
    var availableApps: [Entry] {
        let list: [Entry]
        if saved.mode == "自定义" { return saved.apps }
        if saved.mode == "Dock" { list = dock() } else {
            list = running().filter { a in !saved.excluded.contains { $0.path == a.path } }
        }
        return list.enumerated().map { Entry(path: $0.element.path, key: $0.offset < keys.count ? keys[$0.offset] : "") }
    }
    var modifierFlag: NSEvent.ModifierFlags { switch saved.modifier { case "⌘ Command": return .command; case "⌃ Control": return .control; case "⇧ Shift": return .shift; default: return .option } }
    var silentNow: Bool { guard let p = NSWorkspace.shared.frontmostApplication?.bundleURL?.path else { return false }; return saved.silent.contains { $0.path == p } }
    func activate(_ entry: Entry) {
        dismiss()
        pendingFocus = nil
        activationRequest += 1
        let request = activationRequest
        // Workspace activation must not block the keyboard event-tap callback.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard request == self.activationRequest else { return }
            let running = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == entry.path }
            if let running, running.isActive && self.saved.hideFront {
                running.hide()
            } else {
                // Reopen through Launch Services so an already-running app also
                // restores its windows, even without Accessibility permission.
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:entry.path),configuration:configuration) { app, error in
                    Task { @MainActor in
                        guard request == self.activationRequest else { return }
                        if let error { self.message = error.localizedDescription }
                        else if let app { self.bringToFront(app) }
                    }
                }
            }
            self.saved.count += 1; self.saved.counts[entry.path, default:0] += 1
        }
    }
    func bringToFront(_ app: NSRunningApplication) {
        app.unhide()
        pendingFocus = app.processIdentifier
        if app.isActive {
            pendingFocus = nil
            raiseMainWindow(of:app)
        } else if !app.activate(options:[]) { pendingFocus = nil }
    }
    func raiseMainWindow(of app: NSRunningApplication) {
        guard AXIsProcessTrusted() else { return }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application,0.25)
        var window: AXUIElement?
        for attribute in [kAXMainWindowAttribute,kAXFocusedWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(application,attribute as CFString,&value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                window = (value as! AXUIElement)
                break
            }
        }
        if window == nil {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(application,kAXWindowsAttribute as CFString,&value) == .success,
               let windows = value as? [AXUIElement] {
                window = windows.first { item in
                    var subrole: CFTypeRef?
                    AXUIElementCopyAttributeValue(item,kAXSubroleAttribute as CFString,&subrole)
                    return subrole as? String == kAXStandardWindowSubrole
                }
            }
        }
        guard let window else { return }
        AXUIElementSetAttributeValue(window,kAXMinimizedAttribute as CFString,kCFBooleanFalse)
        AXUIElementSetAttributeValue(window,kAXMainAttribute as CFString,kCFBooleanTrue)
        AXUIElementPerformAction(window,kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window,kAXFocusedAttribute as CFString,kCFBooleanTrue)
    }
    var overlayHeight: CGFloat { 126 + saved.size * 32 }
    func present() {
        guard enabled, !silentNow else { return }
        if sessionApps == nil { sessionApps = availableApps }
        selected = 0; showing = true
        if overlay == nil {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
            p.hidesOnDeactivate = false; p.isReleasedWhenClosed = false
            p.level = .statusBar; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; overlay = p
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            overlay?.contentView = NSHostingView(rootView:SwitchBar(store:self,compact:true))
        } else {
            // Put the glass at the window root so its backdrop is the desktop, not another hosting layer.
            let glass = NSGlassEffectView()
            glass.cornerRadius = 26
            let transparency = saved.glassTransparency ?? .high
            glass.style = transparency == .high ? .clear : .regular
            glass.tintColor = transparency == .low ? NSColor.windowBackgroundColor.withAlphaComponent(0.35) : nil
            let hosting = NSHostingView(rootView:SwitchBar(store:self,compact:false))
            hosting.sizingOptions = []
            glass.contentView = hosting
            overlay?.contentView = glass
        }
        let point = NSEvent.mouseLocation
        let screen = (saved.activeScreen ? NSScreen.screens.first { $0.frame.contains(point) } : NSScreen.main) ?? NSScreen.screens[0]
        let width = min(max(apps.isEmpty ? 280 : 0, CGFloat(apps.count) * (82 + saved.size * 32) + 16), screen.visibleFrame.width - 60)
        let height = overlayHeight
        let area = screen.visibleFrame
        let y = saved.position == "底部" ? area.minY + 40 : saved.position == "顶部" ? area.maxY - height - 40 : area.minY + (area.height-height)*saved.y
        overlay?.setFrame(NSRect(x:area.minX + (area.width-width)*saved.x,y:y,width:width,height:height), display:true)
        overlay?.orderFrontRegardless()
        hideTimer?.invalidate()
        if saved.hideAfter > 0 { hideTimer = Timer.scheduledTimer(withTimeInterval:saved.hideAfter,repeats:false) { [weak self] _ in Task { @MainActor in self?.dismiss() } } }
    }
    func dismiss() { showing = false; overlay?.orderOut(nil); timer?.invalidate(); hideTimer?.invalidate() }
    func choose(_ entry: Entry, with event: NSEvent) {
        consumedKeys.insert(event.keyCode)
        guard eventTap != nil || fallbackHotKeys[event.keyCode] != nil else {
            message = text("此快捷键无法注册，请更换按键或授权辅助功能。")
            return
        }
        if let index = apps.firstIndex(of:entry) { selected = index }
        activate(entry)
    }
    func handle(_ event: NSEvent) -> Bool {
        if event.type == .keyUp, consumedKeys.remove(event.keyCode) != nil {
            if !held && consumedKeys.isEmpty { unregisterFallbackHotKeys() }
            return true
        }
        if event.type == .keyDown, consumedKeys.contains(event.keyCode) { return true }
        if event.type == .keyDown, NSApp.isActive, event.modifierFlags.contains(.command),
           [12,43].contains(event.keyCode) { return false }
        guard !editingShortcut else { held = false; dismiss(); return false }
        if event.type == .flagsChanged {
            let down = event.modifierFlags.contains(modifierFlag)
            if down && !held {
                held = true
                sessionApps = availableApps
                if saved.doublePress && doublePressWindow.press(at: ProcessInfo.processInfo.systemUptime) {
                    enabled.toggle(); dismiss(); return false
                }
                if eventTap == nil && enabled && !(silentNow && saved.disableSilentKeys) { registerFallbackHotKeys() }
                timer?.invalidate()
                if saved.delay != Mechanics.neverDisplayDelay {
                    let displayTimer = Timer(timeInterval:saved.delay,repeats:false) { [weak self] _ in Task { @MainActor in if self?.held == true { self?.present() } } }
                    timer = displayTimer
                    RunLoop.main.add(displayTimer, forMode: .common)
                }
            } else if !down && held {
                held = false
                defer { sessionApps = nil; if consumedKeys.isEmpty { unregisterFallbackHotKeys() } }
                dismiss()
            }
            return false
        }
        guard event.type == .keyDown else { return false }
        // Activation can move focus before the modifier-up event reaches us.
        held = event.modifierFlags.contains(modifierFlag)
        guard held, enabled else { return false }
        if event.isARepeat { return false }
        if silentNow && saved.disableSilentKeys { return false }
        if event.keyCode == 53 { consumedKeys.insert(event.keyCode); dismiss(); return true }
        if [123,124,48].contains(event.keyCode) { consumedKeys.insert(event.keyCode); if !showing { present() }; if !apps.isEmpty { selected = (selected + (event.keyCode == 123 ? apps.count - 1 : 1)) % apps.count }; return true }
        if event.keyCode == 36, showing, apps.indices.contains(selected) { choose(apps[selected],with:event); return true }
        let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
        if let entry = apps.first(where: { !$0.key.isEmpty && $0.key.uppercased() == key }) { choose(entry,with:event); return true }
        return false
    }
    func installMonitor() {
        guard eventTap == nil, local == nil, global == nil else { return }
        // A session event tap consumes assigned keys so they never type into the active app.
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        eventTap = AXIsProcessTrusted() ? CGEvent.tapCreate(tap:.cgSessionEventTap, place:.headInsertEventTap, options:.defaultTap, eventsOfInterest:CGEventMask(mask), callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let store = Unmanaged<Store>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let tap = store.eventTap { CGEvent.tapEnable(tap:tap,enable:true) }; return Unmanaged.passUnretained(event) }
            guard let e = NSEvent(cgEvent:event) else { return Unmanaged.passUnretained(event) }
            return store.handle(e) ? nil : Unmanaged.passUnretained(event)
        }, userInfo:Unmanaged.passUnretained(self).toOpaque()) : nil
        globalShortcutsAvailable = eventTap != nil && AXIsProcessTrusted()
        if let tap = eventTap { eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0); CFRunLoopAddSource(CFRunLoopGetMain(),eventSource,.commonModes); CGEvent.tapEnable(tap:tap,enable:true) }
        else {
            installFallbackMonitor()
            monitorRetry = Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in
                guard let self, AXIsProcessTrusted(), !self.held, !self.showing, self.consumedKeys.isEmpty else { return }
                self.removeMonitor(); self.installMonitor()
            }
        }
    }
    func installFallbackMonitor() {
        var types = [EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)
            guard result == noErr, id.signature == 0x47535743 else { return OSStatus(eventNotHandledErr) }
            let store = Unmanaged<Store>.fromOpaque(context).takeUnretainedValue()
            let code = UInt16(id.id)
            let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let key = store.fallbackCharacters[code] ?? ""
            if let e = NSEvent.keyEvent(with:down ? .keyDown : .keyUp,location:.zero,modifierFlags:store.modifierFlag,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:0,context:nil,characters:key,charactersIgnoringModifiers:key,isARepeat:false,keyCode:code) { _ = store.handle(e) }
            return noErr
        },types.count,&types,Unmanaged.passUnretained(self).toOpaque(),&fallbackHandler)
        local = NSEvent.addLocalMonitorForEvents(matching:[.flagsChanged,.keyDown,.keyUp]) { [weak self] event in self?.handle(event) == true ? nil : event }
        global = NSEvent.addGlobalMonitorForEvents(matching:[.flagsChanged]) { [weak self] e in _ = self?.handle(e) }
    }
    func registerFallbackHotKeys() {
        guard fallbackHandler != nil else { return }
        unregisterFallbackHotKeys()
        // Resolve ASCII keys using the current layout, including Chinese input sources.
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let raw = TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData) else { return }
        let data = unsafeBitCast(raw,to:CFData.self)
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to:UCKeyboardLayout.self)
        let assigned = Set(apps.map { $0.key.uppercased() }.filter { !$0.isEmpty })
        let modifiers: UInt32 = modifierFlag == .command ? UInt32(cmdKey) : modifierFlag == .control ? UInt32(controlKey) : modifierFlag == .shift ? UInt32(shiftKey) : UInt32(optionKey)
        for code in UInt16(0)..<128 {
            var dead: UInt32 = 0; var length = 0
            var chars = [UniChar](repeating:0,count:4)
            let result = UCKeyTranslate(layout,code,UInt16(kUCKeyActionDown),0,UInt32(LMGetKbdType()),OptionBits(kUCKeyTranslateNoDeadKeysMask),&dead,chars.count,&length,&chars)
            let key = result == noErr ? String(utf16CodeUnits:chars,count:length).uppercased() : ""
            guard assigned.contains(key) || [36,48,53,123,124].contains(code) else { continue }
            var reference: EventHotKeyRef?
            if RegisterEventHotKey(UInt32(code),modifiers,EventHotKeyID(signature:0x47535743,id:UInt32(code)),GetApplicationEventTarget(),0,&reference) == noErr, let reference {
                fallbackHotKeys[code] = reference; fallbackCharacters[code] = key
            }
        }
    }
    func unregisterFallbackHotKeys() {
        for reference in fallbackHotKeys.values { UnregisterEventHotKey(reference) }
        fallbackHotKeys.removeAll(); fallbackCharacters.removeAll()
    }
    func resetInteraction() {
        held = false; editingShortcut = false; sessionApps = nil; pendingFocus = nil
        consumedKeys.removeAll()
        unregisterFallbackHotKeys()
        dismiss()
    }
    func removeMonitor() {
        resetInteraction()
        globalShortcutsAvailable = false
        monitorRetry?.invalidate(); monitorRetry = nil
        if let fallbackHandler { RemoveEventHandler(fallbackHandler); self.fallbackHandler = nil }
        if let local { NSEvent.removeMonitor(local); self.local = nil }
        if let global { NSEvent.removeMonitor(global); self.global = nil }
        if let eventTap { CGEvent.tapEnable(tap:eventTap,enable:false); CFMachPortInvalidate(eventTap); self.eventTap = nil }
        if let eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(),eventSource,.commonModes); self.eventSource = nil }
    }
    func pick(_ target: String) {
        let p = NSOpenPanel(); p.allowedContentTypes = [.applicationBundle]; p.allowsMultipleSelection = true; p.directoryURL = URL(fileURLWithPath:"/Applications")
        if p.runModal() == .OK { for url in p.urls { let entry = Entry(path:url.path,key: keys[saved.apps.count % keys.count]); switch target { case "静默模式": if !saved.silent.contains(where:{$0.path==entry.path}) { saved.silent.append(entry) }; case "过滤": if !saved.excluded.contains(where:{$0.path==entry.path}) { saved.excluded.append(entry) }; default: if !saved.apps.contains(where:{$0.path==entry.path}) { saved.apps.append(entry) } } } }
    }
    func exportProfile() { let p = NSSavePanel(); p.nameFieldStringValue = text("quick配置.json"); if p.runModal() == .OK, let url=p.url { do { try JSONEncoder().encode(Profile(name:text("自定义配置"),apps:saved.apps)).write(to:url) } catch { message=error.localizedDescription } } }
    func importProfile() { let p=NSOpenPanel(); p.allowedContentTypes=[.json]; if p.runModal() == .OK, let url=p.url { do { let profile=try JSONDecoder().decode(Profile.self,from:Data(contentsOf:url)); saved.profiles.append(profile); saved.apps=profile.apps; saved.mode="自定义" } catch { message=text("无法导入：")+error.localizedDescription } } }
}

struct AppTile: View {
    let entry: Entry; var language: AppLanguage = .simplifiedChinese; var scale = 0.7; var action: ()->Void
    var body: some View {
        Button(action:action) {
            VStack(spacing:7) {
                Image(nsImage:NSWorkspace.shared.icon(forFile:entry.path))
                    .resizable().interpolation(.high)
                    .frame(width:56 + scale * 32,height:56 + scale * 32)
                Text(entry.name).font(.system(size:12,weight:.medium))
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth:.infinity)
                Text(entry.key.isEmpty ? "—" : entry.key)
                    .font(.system(size:11,weight:.medium))
                    .foregroundStyle(.secondary)
                    .frame(height:16)
            }
            .frame(width:74 + scale * 32).padding(.vertical,4).padding(.horizontal,2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.name)
        .accessibilityValue(entry.key.isEmpty ? "" : language.text("快捷键 %@",entry.key))
    }
}
struct SwitchBarGlass<Content: View>: NSViewRepresentable {
    var transparency: GlassTransparency
    var content: Content
    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = 26
        let hosting = NSHostingView(rootView:content)
        hosting.sizingOptions = []
        glass.contentView = hosting
        return glass
    }
    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        // Embed the icons inside the native material so AppKit composites one glass surface.
        (glass.contentView as? NSHostingView<Content>)?.rootView = content
        glass.style = transparency == .high ? .clear : .regular
        glass.tintColor = transparency == .low ? NSColor.windowBackgroundColor.withAlphaComponent(0.35) : nil
    }
}
struct SwitchBar: View {
    @ObservedObject var store: Store; var compact: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    private let shape = RoundedRectangle(cornerRadius:26,style:.continuous)
    var body: some View {
        if !compact {
            content
        } else if reduceTransparency || contrast == .increased {
            content
                .background(Color(nsColor:.windowBackgroundColor),in:shape)
                .overlay { shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0.12),lineWidth:1) }
        } else {
            SwitchBarGlass(transparency:store.saved.glassTransparency ?? .high,content:content)
                .frame(height:store.overlayHeight)
        }
    }
    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:4) {
                    if store.apps.isEmpty {
                        Text(store.text("暂无 App，请在设置中添加")).font(.callout).foregroundStyle(.secondary).frame(minWidth:260).frame(height:118)
                    }
                    ForEach(Array(store.apps.enumerated()),id:\.element.id) { i,a in
                        AppTile(entry:a,language:store.language,scale:store.saved.size) { store.activate(a) }
                            .id(i)
                    }
                }.padding(.horizontal,10).padding(.vertical,6)
            }
            .onChange(of:store.selected) { _, index in
                withAnimation(reduceMotion ? nil : .spring(response:0.3,dampingFraction:1)) { proxy.scrollTo(index,anchor:.center) }
            }
        }
        .frame(maxWidth:.infinity).frame(height:store.overlayHeight)
    }
}
struct SettingsBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
struct SettingsGlass: ViewModifier {
    var cornerRadius: CGFloat = 22
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius:cornerRadius,style:.continuous)
        if reduceTransparency || contrast == .increased {
            content
                .background(Color(nsColor:.windowBackgroundColor),in:shape)
                .overlay { shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0.12),lineWidth:1) }
        } else {
            content.glassEffect(.regular,in:shape)
        }
    }
}
struct ContentView: View {
    @ObservedObject var store: Store
    let pages = [("配置","square.grid.2x2"),("通用","gearshape"),("外观","paintpalette"),("高级","slider.horizontal.3"),("静默模式","moon"),("用量","chart.bar"),("关于","info.circle")]
    @FocusState var shortcutFocused: Bool
    @State var subpage="通用"; @State var profileName=""; @State var dragID: String?
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:10) {
                    Image(nsImage:AppArtwork.icon).resizable().frame(width:38,height:38)
                    VStack(alignment:.leading,spacing:3) {
                        Text("quick").font(.system(size:18,weight:.semibold))
                        Text(store.text("应用快捷切换")).font(.system(size:11)).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal,10).padding(.top,12).padding(.bottom,20)
                ForEach(pages,id:\.0) { page,icon in
                    Button { store.page=page } label: {
                        Label {
                            Text(store.text(page)).frame(maxWidth:.infinity,alignment:.leading)
                        } icon: {
                            Image(systemName:icon).frame(width:20)
                        }
                        .font(.system(size:13,weight:store.page==page ? .semibold : .medium))
                        .padding(.horizontal,12).padding(.vertical,11)
                        .background {
                            if store.page == page {
                                RoundedRectangle(cornerRadius:12,style:.continuous)
                                    .fill(Color.accentColor.opacity(0.14))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius:12,style:.continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.text(page))
                    .accessibilityAddTraits(store.page == page ? .isSelected : [])
                }
                Spacer(minLength:20)
                HStack {
                    Circle().fill(store.enabled ? .green : .secondary).frame(width:6,height:6)
                    Text(store.text(store.enabled ? "已启用" : "已暂停")).font(.system(size:12,weight:.medium))
                    Spacer()
                    Toggle(store.text("启用切换器"),isOn:$store.enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }.padding(.horizontal,10).padding(.vertical,8)
                Text(store.text("按住 %@ 即刻切换",store.saved.modifier))
                    .font(.system(size:11)).foregroundStyle(.secondary).padding(.horizontal,10)
                Button { NSApp.terminate(nil) } label: {
                    Label(store.text("退出 quick"),systemImage:"power")
                        .font(.system(size:12,weight:.medium))
                        .frame(maxWidth:.infinity)
                        .padding(.vertical,4)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityIdentifier("quick.quit")
                .help(store.text("退出 quick（⌘Q）"))
                .padding(.top,10)
            }
            .padding(14).frame(width:184)
            .modifier(SettingsGlass(cornerRadius:24))
            .padding(.leading,12).padding(.vertical,12)
            VStack(alignment:.leading,spacing:0) {
                HStack(alignment:.center,spacing:20) {
                    VStack(alignment:.leading,spacing:6) {
                        Text(store.text(store.page)).font(.system(size:26,weight:.bold))
                        Text(store.text(subtitle)).font(.system(size:12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength:0)
                    Button { store.present() } label: {
                        Label(store.text("预览切换器"),systemImage:"play.fill")
                    }.buttonStyle(.glass).controlSize(.large)
                }.padding(.horizontal,28).padding(.top,28).padding(.bottom,20)
                ScrollView {
                    GlassEffectContainer(spacing:20) {
                        VStack(alignment:.leading,spacing:20) { pageContent }
                            .padding(.horizontal,28).padding(.vertical,12)
                            .frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
                HStack(spacing:7) {
                    Image(systemName:"keyboard")
                    Text(store.text("%@ + 对应按键",store.saved.modifier))
                    Spacer()
                    Text("quick")
                }
                .font(.system(size:11)).foregroundStyle(.secondary)
                .padding(.horizontal,28).padding(.vertical,16)
            }.frame(maxWidth:.infinity)
        }
        .environment(\.locale,store.language.locale)
        .background { SettingsBackdrop().ignoresSafeArea() }
        .buttonStyle(.bordered)
        .toggleStyle(.switch)
        .frame(minWidth:860,minHeight:650)
        .onChange(of: shortcutFocused) { _, focused in store.editingShortcut = focused }
        .onAppear { store.refreshLoginItemStatus() }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in store.refreshLoginItemStatus() }
        .onDisappear { store.editingShortcut = false }
        .alert(store.text("提示"),isPresented:Binding(get:{!store.message.isEmpty},set:{if !$0 {store.message=""}})) { Button(store.text("好")) {store.message=""} } message:{ Text(store.message) }
    }
    var subtitle: String { switch store.page { case "配置":return "为每一个 App，安排一个顺手的快捷键。"; case "外观":return "让切换器融入你的桌面。"; case "静默模式":return "专注时，让切换器安静下来。"; case "高级":return "调整激活方式与切换行为。"; case "用量":return "记录每一次更流畅的切换。"; default:return "按你的习惯，设置快捷切换。" } }
    func card<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:16) {
            Text(store.text(title)).font(.system(size:13,weight:.semibold))
            content()
        }
        .padding(22).frame(maxWidth:.infinity,alignment:.leading)
        .modifier(SettingsGlass())
    }
    @ViewBuilder var pageContent: some View {
        switch store.page {
        case "配置": configuration
        case "外观":
            card("实时预览") { SwitchBar(store:store,compact:false); Text(store.text("原生 Liquid Glass 背景，透明度越高越通透；开启系统“减少透明度”时使用不透明背景。")).font(.caption).foregroundStyle(.secondary) }
            card("App 条") {
                Picker(store.text("背景透明度"),selection:Binding(get:{store.saved.glassTransparency ?? .high},set:{store.saved.glassTransparency=$0})) {
                    ForEach(GlassTransparency.allCases,id:\.self) { Text(store.text($0.rawValue)).tag($0) }
                }.pickerStyle(.segmented)
                slider("大小",value:$store.saved.size,range:0.3...1.5)
                Picker(store.text("位置"),selection:$store.saved.position) { ForEach(["顶部","中部","底部"],id:\.self) {Text(store.text($0)).tag($0)} }.pickerStyle(.segmented)
                slider("水平位置",value:$store.saved.x,range:0...1); slider("垂直位置",value:$store.saved.y,range:0...1)
                Button(store.text("还原默认")) {store.saved.glassTransparency = .high;store.saved.size=0.7;store.saved.x=0.5;store.saved.y=0.5;store.saved.position="中部"}
            }
        case "高级":
            card("激活快捷键") { Picker(store.text("按住"),selection:$store.saved.modifier) { ForEach(["⌥ Option","⌘ Command","⌃ Control","⇧ Shift"],id:\.self) {Text(store.text($0)).tag($0)} }; slider("显示延迟（2.5 为从不显示）",value:$store.saved.delay,range:0...Mechanics.neverDisplayDelay); slider("自动隐藏（0 为从不）",value:$store.saved.hideAfter,range:0...15); Toggle(store.text("双击激活键以暂停或启用"),isOn:$store.saved.doublePress) }
            card("切换行为") { Toggle(store.text("App 已在最前时，再次切换会隐藏它"),isOn:$store.saved.hideFront); Toggle(store.text("在光标所在屏幕显示"),isOn:$store.saved.activeScreen) }
        case "静默模式":
            card("静默名单") { Text(store.text("当前 App 在此列表中时，不显示切换器。")).font(.caption).foregroundStyle(.secondary); entries(store.saved.silent,target:"静默模式"); Button(store.text("添加 App…"),systemImage:"plus") {store.pick("静默模式")}; Toggle(store.text("同时禁用这些 App 内的切换快捷键"),isOn:$store.saved.disableSilentKeys) }
        case "用量":
            card("切换统计") { HStack(alignment:.firstTextBaseline) { Text("\(store.saved.count)").font(.system(size:48,weight:.light,design:.rounded)); Text(store.text("次切换")).foregroundStyle(.secondary) }; if store.saved.count==0 {Text(store.text("开始使用后，你的切换记录会显示在这里。")).foregroundStyle(.secondary)}; ForEach(store.saved.counts.sorted{$0.value > $1.value},id:\.key) { p,c in HStack {Text(Entry(path:p,key:"").name).frame(width:130,alignment:.leading); GeometryReader {g in RoundedRectangle(cornerRadius:4).fill(.blue.gradient).frame(width:max(4,g.size.width*CGFloat(c)/CGFloat(max(store.saved.count,1))))}.frame(height:12);Text("\(c)") } } }
        case "关于":card("quick") { Image(nsImage:AppArtwork.icon).resizable().frame(width:80,height:80); Text(store.text("Swift 原生应用")).font(.title2); Text(store.text("为 macOS 27 构建，使用系统 Liquid Glass 材质。\n独立重建的应用切换工具，未使用原应用品牌素材。")).foregroundStyle(.secondary); Text(store.text("版本 %@",Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.6")).font(.caption) }
        default:
            card("语言") {
                Picker(store.text("语言"),selection:Binding(get:{store.language},set:{store.saved.language=$0})) {
                    ForEach(AppLanguage.allCases,id:\.self) { Text($0.name).tag($0) }
                }
            }
            card("启动与菜单栏") {
                Toggle(store.text("显示菜单栏图标"),isOn:$store.saved.showStatus)
                Toggle(store.text("登录时启动"),isOn:Binding(get:{store.loginItemStatus == .enabled},set:{store.setLaunchAtLogin($0)}))
                if store.loginItemStatus == .requiresApproval {
                    Text(store.text("已注册登录项，等待系统批准。请在系统设置的“登录项与扩展”中允许 quick 登录时启动。")).font(.caption).foregroundStyle(.secondary)
                    Button(store.text("打开登录项设置")) { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            card("系统权限") { Label(store.text(store.globalShortcutsAvailable ? "全局快捷键已就绪" : "长按显示浮层后，可使用按键切换"),systemImage:store.globalShortcutsAvailable ? "checkmark.shield" : "keyboard"); Text(store.text("辅助功能授权后，可恢复并前置目标主窗口、设置键盘焦点，并直接使用快捷键；授权状态会自动更新。")).font(.caption).foregroundStyle(.secondary); Button(store.text("打开辅助功能设置")) {NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)} }
        }
    }
    func slider(_ name:String,value:Binding<Double>,range:ClosedRange<Double>)->some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(alignment:.firstTextBaseline) {
                Text(store.text(name))
                Spacer(minLength:12)
                Text(String(format:"%.2f",value.wrappedValue))
                    .monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size:12))
            Slider(value:value,in:range).accessibilityLabel(store.text(name))
        }
    }
    var configuration: some View {
        VStack(alignment:.leading,spacing:20) {
            Picker(store.text("模式"),selection:$store.saved.mode) {ForEach(["Dock","切换器","自定义"],id:\.self){Text(store.text($0)).tag($0)}}.pickerStyle(.segmented).labelsHidden().controlSize(.large)
            card(store.text("%@ 模式",store.text(store.saved.mode))) {
                Text(store.text(store.saved.mode == "Dock" ? "与 Dock 中的 App 保持一致，按对应按键快速直达。" : store.saved.mode == "切换器" ? "显示正在运行的 App，保留系统顺序，切换后位置不变。" : "自由添加 App，拖动排序，并为每个 App 设置快捷键。")).font(.system(size:12)).foregroundStyle(.secondary)
                SwitchBar(store:store,compact:false)
                HStack {Label(store.text("按住 %@",store.saved.modifier),systemImage:"option"); Text("→").foregroundStyle(.tertiary);Text(store.text("按下对应字符"));Spacer();Text(store.text("%@ 个 App",String(store.apps.count))).foregroundStyle(.secondary)}.font(.caption)
                if store.saved.mode == "Dock" {Toggle(store.text("将访达作为第一个 App"),isOn:$store.saved.finderFirst)}
            }
            if store.saved.mode == "自定义" {
                card("App 与快捷键") {entries(store.saved.apps,target:"自定义");HStack {Button(store.text("添加 App…"),systemImage:"plus"){store.pick("自定义")};Button(store.text("从 Dock 载入")){store.saved.apps=store.dock().enumerated().map{Entry(path:$0.element.path,key:store.keys[$0.offset % store.keys.count])}};Button(store.text("从切换器载入")){store.saved.apps=store.running().enumerated().map{Entry(path:$0.element.path,key:store.keys[$0.offset % store.keys.count])}}}}
                card("自定义配置") {HStack {TextField(store.text("配置名称"),text:$profileName);Button(store.text("保存配置")){store.saved.profiles.append(Profile(name:profileName.isEmpty ? store.text("新配置") : profileName,apps:store.saved.apps))}};ForEach(store.saved.profiles){p in HStack {Text(p.name);Spacer();Button(store.text("载入")){store.saved.apps=p.apps};Button(role:.destructive){store.saved.profiles.removeAll{$0.id==p.id}}label:{Image(systemName:"trash")}.help(store.text("删除配置 %@",p.name)).accessibilityLabel(store.text("删除配置 %@",p.name))}};HStack {Button(store.text("导入…")){store.importProfile()};Button(store.text("导出…")){store.exportProfile()}} }
            } else {
                card("快捷键设置") {Picker(store.text("字符"),selection:$store.saved.characters){ForEach(["数字和字母","仅数字","仅字母"],id:\.self){Text(store.text($0)).tag($0)}};Picker(store.text("键盘布局"),selection:$store.saved.keyboard){ForEach(["全键盘","左手区域","右手区域"],id:\.self){Text(store.text($0)).tag($0)}}}
                if store.saved.mode == "切换器" {card("过滤 App") {entries(store.saved.excluded,target:"过滤");Button(store.text("添加要排除的 App…")){store.pick("过滤")}}}
            }
        }
    }
    func entries(_ list:[Entry],target:String)->some View {
        VStack(spacing:8) {if list.isEmpty {Text(store.text("尚未添加 App")).font(.caption).foregroundStyle(.secondary).padding(10)}
            ForEach(list) {entry in HStack {Image(nsImage:NSWorkspace.shared.icon(forFile:entry.path)).resizable().frame(width:28,height:28);Text(entry.name);Spacer();if target=="自定义" {TextField(store.text("按键"),text:Binding(get:{store.saved.apps.first{$0.path==entry.path}?.key ?? ""},set:{new in let key=new.uppercased();guard key.isEmpty || (key.count == 1 && "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".contains(key)) else {store.message=store.text("请输入单个英文字母或数字。");return};guard !store.saved.apps.contains(where:{$0.path != entry.path && $0.key==key && !key.isEmpty}) else {store.message=store.text("按键 %@ 已被其他 App 使用，请选择其他按键。",key);return};if let i=store.saved.apps.firstIndex(where:{$0.path==entry.path}){store.saved.apps[i].key=key}})).frame(width:45).textFieldStyle(.roundedBorder).focused($shortcutFocused)};Button {switch target{case "静默模式":store.saved.silent.removeAll{$0.path==entry.path};case "过滤":store.saved.excluded.removeAll{$0.path==entry.path};default:store.saved.apps.removeAll{$0.path==entry.path}}}label:{Image(systemName:"minus.circle").foregroundStyle(.secondary)}.buttonStyle(.borderless).help(store.text("移除 %@",entry.name)).accessibilityLabel(store.text("移除 %@",entry.name))}.padding(6).background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:7)).onDrag {dragID=entry.path;return NSItemProvider(object:entry.path as NSString)}.onDrop(of:[.text],isTargeted:nil){_ in guard target=="自定义",let dragID,let from=store.saved.apps.firstIndex(where:{$0.path==dragID}),let to=store.saved.apps.firstIndex(where:{$0.path==entry.path}) else{return false};store.saved.apps.move(fromOffsets:IndexSet(integer:from),toOffset:to>from ? to+1 : to);return true} }
        }
    }
}

class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let updaterController = SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:nil,userDriverDelegate:nil)
    let store=Store(); var window:NSWindow!;var status:NSStatusItem?; var screenshot:String?; var languageObserver: AnyCancellable?
    func applicationDidFinishLaunching(_ notification:Notification) {
        let args=CommandLine.arguments
        if let i=args.firstIndex(of:"--screenshot"),args.count>i+1{screenshot=args[i+1]}
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppArtwork.icon
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:740),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.delegate = self
        window.title="quick";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.isReleasedWhenClosed=false
        window.titlebarSeparatorStyle = .none
        window.isOpaque=false;window.backgroundColor = .clear
        let settingsView = NSHostingView(rootView:ContentView(store:store))
        settingsView.wantsLayer = true
        settingsView.layer?.cornerRadius = 26
        settingsView.layer?.cornerCurve = .continuous
        settingsView.layer?.masksToBounds = true
        window.contentView=settingsView;window.center()
        if screenshot == nil {window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);store.installMonitor()} else {window.orderFront(nil)}
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status?.button?.image = AppArtwork.statusIcon
        status?.button?.toolTip = "quick"
        status?.button?.setAccessibilityLabel("quick")
        status?.isVisible = store.saved.showStatus
        if screenshot == nil { updaterController.startUpdater() }
        updateMenus()
        languageObserver = store.$saved.map { $0.language }.removeDuplicates().dropFirst().sink { [weak self] _ in
            // @Published emits before the new settings are assigned.
            DispatchQueue.main.async { self?.updateMenus() }
        }
        Timer.scheduledTimer(withTimeInterval:0.5,repeats:true){[weak self]_ in guard let self else{return};self.status?.isVisible=self.store.saved.showStatus}
        if let screenshot { var frames=0;Timer.scheduledTimer(withTimeInterval:1.0/60,repeats:true){[weak self]t in frames+=1;guard frames>=120,let self,let view=self.window.contentView else{return};t.invalidate();self.window.displayIfNeeded();guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{exit(2)};view.cacheDisplay(in:view.bounds,to:bitmap);guard let png=bitmap.representation(using:.png,properties:[:]) else{exit(3)};do{try FileManager.default.createDirectory(at:URL(fileURLWithPath:screenshot).deletingLastPathComponent(),withIntermediateDirectories:true);try png.write(to:URL(fileURLWithPath:screenshot));print("Screenshot saved: \(screenshot)")}catch{print(error);exit(4)};NSApp.terminate(nil)} }
    }
    func updateMenus() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle:store.text("打开设置…"),action:#selector(openSettings),keyEquivalent:",").target = self
        appMenu.addItem(withTitle:store.text("检查更新…"),action:#selector(SPUStandardUpdaterController.checkForUpdates(_:)),keyEquivalent:"").target = updaterController
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:store.text("退出quick"),action:#selector(quit),keyEquivalent:"q").target = self
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
        let menu = NSMenu()
        menu.addItem(withTitle:store.text("打开设置…"),action:#selector(openSettings),keyEquivalent:",").target = self
        menu.addItem(withTitle:store.text("启用 / 暂停"),action:#selector(toggle),keyEquivalent:"").target = self
        menu.addItem(withTitle:store.text("检查更新…"),action:#selector(SPUStandardUpdaterController.checkForUpdates(_:)),keyEquivalent:"").target = updaterController
        menu.addItem(.separator())
        menu.addItem(withTitle:store.text("退出quick"),action:#selector(quit),keyEquivalent:"q").target = self
        status?.menu = menu
    }
    func windowWillClose(_ notification:Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else { return }
        store.resetInteraction()
        NSApp.setActivationPolicy(.accessory)
    }
    @objc func openSettings(){store.resetInteraction();NSApp.setActivationPolicy(.regular);window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    @objc func toggle(){store.enabled.toggle()}
    @objc func quit(){store.removeMonitor();NSApp.terminate(nil)}
    func applicationWillTerminate(_ notification:Notification){store.removeMonitor()}
    func applicationDidResignActive(_ notification:Notification){store.editingShortcut = false}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{openSettings();return true}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{false}
}
let app=NSApplication.shared
let delegate=Delegate()
app.delegate=delegate
app.run()
