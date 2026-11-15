import AppKit
import FlutterMacOS

/// The application side of rotide.dm on macOS: one window per Flutter engine (the start window and every document),
/// opening files, the menu bar, the Dock menu, quitting with unsaved documents, preferences shared by all windows.
public final class RotideApp: NSObject {
    public static let shared = RotideApp()

    /// Set by the runner: registers the generated plugins with a new engine.
    public var registerPlugins: ((FlutterViewController) -> Void)?

    private(set) var windows: [RotideWindowController] = []
    private var start: RotideWindowController? { windows.first { $0.kind == .start } }
    var documents: [RotideWindowController] { windows.filter { $0.kind == .document } }
    private var launched = false
    private var pendingPaths: [String] = []
    private var terminating = false

    // MARK: Application delegate

    public func applicationWillFinishLaunching() {
        NSApp.mainMenu = MainMenu.make()
        MainMenu.applyPreferences()
        Appearance.apply(Preferences.string("appearance") ?? "system")
        IconManager.shared.applyAtLaunch()
        // Save panels open expanded, with the sidebar and the folder contents.
        UserDefaults.standard.register(defaults: ["NSNavPanelExpandedStateForSaveMode": true, "NSNavPanelExpandedStateForSaveMode2": true])
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    public func applicationDidFinishLaunching() {
        launched = true
        let paths = pendingPaths
        pendingPaths.removeAll()
        paths.forEach(openDocument)
        // Files passed at launch are already opening; the start window is for an empty launch only.
        DispatchQueue.main.async { [self] in
            if documents.isEmpty { showStart() }
        }
    }

    public func open(urls: [URL]) {
        for url in urls where url.isFileURL {
            if launched { openDocument(url.path) } else { pendingPaths.append(url.path) }
        }
    }

    public func dockMenu() -> NSMenu { RecentMenu.make(title: Language.current.text("недавние"), includeClear: false) }

    public func shouldHandleReopen(hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showStart() }
        return false
    }

    /// Asks every document window, one after another, whether it may close; any "no" cancels quitting.
    public func shouldTerminate() -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateCancel }
        let pending = documents
        guard !pending.isEmpty else { return .terminateNow }
        terminating = true
        askNext(pending[...])
        return .terminateLater
    }

    private func askNext(_ rest: ArraySlice<RotideWindowController>) {
        guard let first = rest.first else {
            terminating = false
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }
        first.askToClose { [self] allowed in
            if allowed { askNext(rest.dropFirst()) } else {
                terminating = false
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
    }

    /// Quit from the Dock, AppleScript or logout goes through the normal terminate path with its save questions.
    func claimQuitEvent() {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleQuit(_:withReply:)),
                                                     forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))
    }

    @objc private func handleQuit(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        NSApp.terminate(nil)
    }

    // MARK: Windows

    func openDocument(_ path: String) {
        let standard = URL(fileURLWithPath: path).standardizedFileURL.path
        if let existing = documents.first(where: { $0.path == standard }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = RotideWindowController(kind: .document, path: standard)
        add(controller)
    }

    @objc func newDocument() {
        add(RotideWindowController(kind: .document, path: nil))
    }

    @objc func showStart() {
        if let start {
            start.window?.makeKeyAndOrderFront(nil)
            return
        }
        add(RotideWindowController(kind: .start, path: nil))
    }

    /// Shows a standalone open panel, as the system's "Open" command does.
    @objc func openPanel() {
        let panel = Panels.openPanel()
        panel.begin { [self] response in
            guard response == .OK else { return }
            for url in panel.urls { openDocument(url.path) }
        }
    }

    @objc func showSettings() {
        guard let target = keyController ?? start else { return }
        target.send("menu", ["command": "settings"])
    }

    private func add(_ controller: RotideWindowController) {
        windows.append(controller)
        controller.load()
        if controller.kind == .document, let start {
            start.close()
        }
    }

    func removed(_ controller: RotideWindowController) {
        windows.removeAll { $0 === controller }
    }

    var keyController: RotideWindowController? {
        windows.first { $0.window === NSApp.keyWindow } ?? windows.first { $0.window === NSApp.mainWindow }
    }

    func controller(for viewController: NSViewController?) -> RotideWindowController? {
        windows.first { $0.flutter === viewController }
    }

    // MARK: Shared state

    /// Sends a preference change to every window, so all of them follow theme, material, zoom and history.
    func broadcast(_ method: String, _ arguments: Any?) {
        for controller in windows { controller.send(method, arguments) }
    }

    @objc private func accessibilityChanged() {
        broadcast("accessibility", Accessibility.current())
    }
}

enum Appearance {
    static func apply(_ value: String) {
        switch value {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}

enum Accessibility {
    static func current() -> [String: Bool] {
        let workspace = NSWorkspace.shared
        return [
            "reduceMotion": workspace.accessibilityDisplayShouldReduceMotion,
            "reduceTransparency": workspace.accessibilityDisplayShouldReduceTransparency,
            "increaseContrast": workspace.accessibilityDisplayShouldIncreaseContrast,
        ]
    }
}

/// Preferences live in the standard user defaults of app.rotide.dm, the same keys the Swift version used, so history
/// and settings carry over and the Dock tile plug-in can read them while the app is closed.
enum Preferences {
    static func string(_ key: String) -> String? { UserDefaults.standard.string(forKey: key) }
    static var recentPaths: [String] { UserDefaults.standard.stringArray(forKey: "recentDocumentPaths") ?? [] }

    static func set(_ key: String, _ value: Any?) {
        if let value, !(value is NSNull) { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        RotideApp.shared.broadcast("preference", ["key": key, "value": value ?? NSNull()])
        if key == "capitalizedLabels" || key == "language" { MainMenu.applyPreferences() }
        if key == "recentDocumentPaths" {
            DistributedNotificationCenter.default().postNotificationName(IconManager.changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
        }
    }

    static func all() -> [String: Any] {
        var values: [String: Any] = [:]
        for key in ["appearance", "frosted", "transparency", "zoom", "appIcon", "capitalizedLabels", "language", "sidebar", "sidebarWidth", "recentDocumentPaths"] {
            if let value = UserDefaults.standard.object(forKey: key) { values[key] = value }
        }
        return values
    }
}

/// The recent files menu: the file menu's "open recent" and the Dock menu, both from the stored history.
final class RecentMenu: NSObject, NSMenuDelegate {
    static let shared = RecentMenu()

    static func make(title: String, includeClear: Bool) -> NSMenu {
        let menu = NSMenu(title: title)
        fill(menu, includeClear: includeClear)
        return menu
    }

    static func fill(_ menu: NSMenu, includeClear: Bool) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let paths = Preferences.recentPaths
        for path in paths {
            let item = NSMenuItem(title: (path as NSString).lastPathComponent, action: #selector(RecentMenu.openRecent(_:)), keyEquivalent: "")
            item.target = shared
            item.representedObject = path
            item.toolTip = path
            menu.addItem(item)
        }
        if includeClear {
            if !paths.isEmpty { menu.addItem(.separator()) }
            let clear = NSMenuItem(title: Language.current.text("очистить меню"), action: #selector(RecentMenu.clear(_:)), keyEquivalent: "")
            clear.target = shared
            clear.isEnabled = !paths.isEmpty
            menu.addItem(clear)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { Self.fill(menu, includeClear: true) }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        RotideApp.shared.openDocument(path)
    }

    @objc func clear(_ sender: Any?) { Preferences.set("recentDocumentPaths", [String]()) }
}
