import AppKit

/// Loaded by the Dock while rotide.dm is kept in the Dock and not running: draws the icon chosen in settings (so the
/// tile does not fall back to the default one after quitting) and offers the recent files on a right click.
/// It reads the preferences of the app it is bundled in and the icon images bundled with the app.
@objc(RotideDockTile)
final class RotideDockTile: NSObject, NSDockTilePlugIn {
    private weak var tile: NSDockTile?
    private var observer: NSObjectProtocol?

    func setDockTile(_ dockTile: NSDockTile?) {
        tile = dockTile
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        guard dockTile != nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("app.rotide.dm.dockTileChanged"),
                                                                        object: nil, queue: .main) { [weak self] _ in self?.update() }
        update()
    }

    private var appBundle: Bundle? {
        // .../rotide.dm.app/Contents/PlugIns/RotideDockTile.docktileplugin
        let plugin = Bundle(for: RotideDockTile.self).bundleURL
        return Bundle(url: plugin.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
    }

    /// Preferences of the application this plug-in is inside (app.rotide.dm, or a test copy's own identifier).
    private func preference(_ key: String) -> Any? {
        let domain = (appBundle?.bundleIdentifier ?? "app.rotide.dm") as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key as CFString, domain)
    }

    private func update() {
        guard let tile else { return }
        let name = preference("appIcon") as? String ?? "default"
        let image = name == "default" ? nil : appBundle.flatMap { bundle -> NSImage? in
            let url = bundle.privateFrameworksURL?.appendingPathComponent("App.framework/Resources/flutter_assets/assets/icons/\(name).png")
            return url.flatMap { NSImage(contentsOf: $0) }
        }
        if let image {
            let view = NSImageView(image: image)
            view.imageScaling = .scaleProportionallyUpOrDown
            tile.contentView = view
        } else {
            tile.contentView = nil
        }
        tile.display()
    }

    func dockMenu() -> NSMenu? {
        let paths = preference("recentDocumentPaths") as? [String] ?? []
        guard !paths.isEmpty else { return nil }
        let menu = NSMenu(title: "недавние")
        for path in paths {
            let item = NSMenuItem(title: (path as NSString).lastPathComponent, action: #selector(open(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = path
            item.toolTip = path
            menu.addItem(item)
        }
        return menu
    }

    @objc private func open(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String, let app = appBundle?.bundleURL else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
