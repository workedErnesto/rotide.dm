import AppKit
import FlutterMacOS

/// The chosen application icon in every state of the app:
/// 1. running: the Dock tile and the app switcher (`applicationIconImage`);
/// 2. closed but kept in the Dock: the RotideDockTile plug-in inside the bundle draws the same image, told about
///    changes by a distributed notification;
/// 3. Finder, Launchpad and Spotlight: a custom icon on the application bundle (`NSWorkspace.setIcon`).
/// The images are the ones the Flutter side shows in settings, read from the bundled Flutter assets.
final class IconManager {
    static let shared = IconManager()
    static let names = ["default", "stone", "blue", "green", "lavender", "terracotta"]
    static let changedNotification = Notification.Name("app.rotide.dm.dockTileChanged")

    private var current: String { Preferences.string("appIcon") ?? "default" }

    /// The 1024-pixel image of a variant from the Flutter assets in the bundle.
    func image(_ name: String) -> NSImage? {
        let variant = Self.names.contains(name) ? name : "default"
        let key = FlutterDartProject.lookupKey(forAsset: "assets/icons/\(variant).png")
        // The key is relative to the application bundle (Contents/Frameworks/App.framework/Resources/flutter_assets/...).
        let candidates: [URL?] = [
            Bundle.main.bundleURL.appendingPathComponent(key),
            Bundle.main.privateFrameworksURL?.appendingPathComponent("App.framework/Resources/flutter_assets/assets/icons/\(variant).png"),
        ]
        for url in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) { return image }
        }
        NSLog("rotide.dm: icon image %@ not found under %@", key, Bundle.main.privateFrameworksURL?.path ?? "")
        return nil
    }

    func pngData(_ name: String, pixels: Int) -> Data? {
        guard let image = image(name) else { return nil }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    func applyAtLaunch() { apply(current, interactive: false) }

    func apply(_ name: String, interactive: Bool) {
        if name == "default" {
            NSApp.applicationIconImage = nil
        } else if let image = image(name) {
            NSApp.applicationIconImage = image
        }
        DistributedNotificationCenter.default().postNotificationName(Self.changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
        applyToBundle(name)
    }

    /// Finder shows a custom bundle icon. It is written only when it differs from the one already applied, so a launch
    /// does not touch the bundle; an update replaces the bundle, and the next launch writes it again.
    private func applyToBundle(_ name: String) {
        let bundle = Bundle.main.bundlePath
        let marker = (bundle as NSString).appendingPathComponent("Icon\r")
        let applied = UserDefaults.standard.string(forKey: "appliedBundleIcon")
        let hasCustom = FileManager.default.fileExists(atPath: marker)
        if name == "default" {
            guard hasCustom else { return }
            NSWorkspace.shared.setIcon(nil, forFile: bundle, options: [])
            UserDefaults.standard.removeObject(forKey: "appliedBundleIcon")
        } else {
            guard !(hasCustom && applied == name), let image = image(name) else { return }
            if NSWorkspace.shared.setIcon(image, forFile: bundle, options: []) {
                UserDefaults.standard.set(name, forKey: "appliedBundleIcon")
            }
        }
        NSWorkspace.shared.noteFileSystemChanged(bundle)
    }
}

/// SF Symbols drawn into template bitmaps at twice their point size, for the Flutter interface to tint.
enum Symbols {
    static func render(name: String, size: Double, weight: Int) -> Data? {
        let symbolWeight: NSFont.Weight
        switch weight {
        case ..<350: symbolWeight = .light
        case ..<450: symbolWeight = .regular
        case ..<550: symbolWeight = .medium
        case ..<650: symbolWeight = .semibold
        default: symbolWeight = .bold
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: symbolWeight, scale: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return nil }
        let scale: CGFloat = 2
        let width = Int((symbol.size.width * scale).rounded(.up)), height = Int((symbol.size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = symbol.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let rect = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: rect)
        NSColor.black.set()
        rect.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
