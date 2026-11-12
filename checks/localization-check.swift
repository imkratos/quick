let app = NSApplication.shared
let settingsKey = "GlassSwitch.settings.v1"
let originalSettings = UserDefaults.standard.data(forKey:settingsKey)
defer {
    if let originalSettings { UserDefaults.standard.set(originalSettings,forKey:settingsKey) }
    else { UserDefaults.standard.removeObject(forKey:settingsKey) }
}

// Existing settings without a language must retain their apps, shortcuts and profiles.
var existing = Saved()
existing.mode = "自定义"
existing.apps = [Entry(path:"/System/Library/CoreServices/Finder.app",key:"F")]
existing.profiles = [Profile(name:"我的配置",apps:existing.apps)]
existing.characters = "仅字母"
existing.keyboard = "左手区域"
existing.position = "顶部"
var legacy = try JSONSerialization.jsonObject(with:JSONEncoder().encode(existing)) as! [String:Any]
legacy.removeValue(forKey:"language")
UserDefaults.standard.set(try JSONSerialization.data(withJSONObject:legacy),forKey:settingsKey)
let store = Store()
precondition(store.language == .simplifiedChinese)
precondition(store.saved.apps == existing.apps && store.saved.profiles.first?.name == "我的配置")
let originalKeys = store.keys
store.saved.language = .english
precondition(store.text("配置") == "Configuration")
precondition(store.text("%@ 模式",store.text(store.saved.mode)) == "Custom Mode")
precondition(store.text("删除配置 %@","我的配置 100%") == "Delete profile 我的配置 100%")
precondition(store.keys == originalKeys && store.availableApps == existing.apps)
precondition(store.saved.position == "顶部" && store.saved.characters == "仅字母")
let reloaded = Store()
precondition(reloaded.language == .english && reloaded.saved.apps == existing.apps)
precondition(reloaded.saved.profiles.first?.name == "我的配置")
store.saved.language = .simplifiedChinese
precondition(store.text("%@ 模式",store.text(store.saved.mode)) == "自定义 模式")
precondition(store.text("按住 %@","⌥ Option") == "按住 ⌥ Option")
for (key,value) in AppLanguage.englishText {
    precondition(value.range(of:"\\p{Han}",options:.regularExpression) == nil, "Untranslated: \(key)")
    precondition(key.components(separatedBy:"%@").count == value.components(separatedBy:"%@").count)
}

let delegate = Delegate()
delegate.store.saved.language = .english
delegate.updateMenus()
precondition(app.mainMenu?.items.first?.submenu?.items.first?.title == "Open Settings…")
delegate.store.saved.language = .simplifiedChinese
delegate.updateMenus()
precondition(app.mainMenu?.items.first?.submenu?.items.first?.title == "打开设置…")
print("语言检查通过：旧配置兼容、双向切换、持久化、快捷键和自定义名称保留、格式占位符、菜单翻译")

if CommandLine.arguments.count > 1 {
    let directory = URL(fileURLWithPath:CommandLine.arguments[1])
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:740),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false
    store.saved.language = .english
    let view = NSHostingView(rootView:ContentView(store:store))
    window.contentView = view
    window.orderFront(nil)
    for (index,page) in ["通用","配置","外观","高级","静默模式","用量","关于"].enumerated() {
        store.page = page
        RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        window.displayIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds)!
        view.cacheDisplay(in:view.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("english-\(index).png"))
    }
    window.orderOut(nil)
    print("已保存七个英语页面预览")
}
