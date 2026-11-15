import AppKit
import FlutterMacOS
import UniformTypeIdentifiers

/// The bridge of one engine: Dart calls on `rotide/native`, and the window, menu and preference events sent back.
public final class RotideNativePlugin: NSObject, FlutterPlugin {
    private weak var registrar: FlutterPluginRegistrar?
    private let channel: FlutterMethodChannel

    private init(registrar: FlutterPluginRegistrar, channel: FlutterMethodChannel) {
        self.registrar = registrar
        self.channel = channel
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "rotide/native", binaryMessenger: registrar.messenger)
        let plugin = RotideNativePlugin(registrar: registrar, channel: channel)
        registrar.addMethodCallDelegate(plugin, channel: channel)
        registrar.register(PreviewFactory(messenger: registrar.messenger), withId: "rotide/preview")
        RotideApp.shared.controller(for: registrar.viewController)?.channel = channel
    }

    private var controller: RotideWindowController? { RotideApp.shared.controller(for: registrar?.viewController) }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "launch":
            guard let controller else { return result(nil) }
            var info: [String: Any] = ["kind": controller.kind.rawValue, "path": controller.path ?? NSNull()]
            info["preferences"] = Preferences.all()
            info["accessibility"] = Accessibility.current()
            info["fullScreen"] = controller.window?.styleMask.contains(.fullScreen) ?? false
            info["version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            result(info)
        case "ready":
            controller?.reveal()
            result(nil)
        case "setFrost":
            controller?.setFrost(args["enabled"] as? Bool ?? true)
            result(nil)
        case "setDocument":
            controller?.setDocument(path: args["path"] as? String, title: args["title"] as? String ?? "", edited: args["edited"] as? Bool ?? false)
            result(nil)
        case "setState":
            controller?.state = args
            result(nil)
        case "drag":
            controller?.dragWindow()
            result(nil)
        case "doubleClick":
            controller?.titleBarDoubleClick()
            result(nil)
        case "close":
            controller?.closeNow()
            result(nil)
        case "performClose":
            controller?.window?.performClose(nil)
            result(nil)
        case "openDocument":
            if let path = args["path"] as? String { RotideApp.shared.openDocument(path) }
            result(nil)
        case "newDocument":
            RotideApp.shared.newDocument()
            result(nil)
        case "showStart":
            RotideApp.shared.showStart()
            result(nil)
        case "openPanel":
            RotideApp.shared.openPanel()
            result(nil)
        case "savePanel":
            guard let window = controller?.window else { return result(nil) }
            Panels.save(in: window, title: args["title"] as? String ?? "", prompt: args["prompt"] as? String,
                        name: args["name"] as? String ?? "", directory: args["directory"] as? String,
                        fileExtension: args["extension"] as? String ?? "md", completion: result)
        case "preferences":
            result(Preferences.all())
        case "setPreference":
            guard let key = args["key"] as? String else { return result(nil) }
            Preferences.set(key, args["value"])
            if key == "appearance" { Appearance.apply(args["value"] as? String ?? "system") }
            result(nil)
        case "setIcon":
            IconManager.shared.apply(args["name"] as? String ?? "default", interactive: true)
            result(nil)
        case "iconImage":
            result(IconManager.shared.pngData(args["name"] as? String ?? "default", pixels: args["pixels"] as? Int ?? 96).map { FlutterStandardTypedData(bytes: $0) })
        case "symbols":
            let requests = args["requests"] as? [[String: Any]] ?? []
            result(requests.map { request -> Any in
                Symbols.render(name: request["name"] as? String ?? "", size: request["size"] as? Double ?? 13,
                               weight: request["weight"] as? Int ?? 500).map { FlutterStandardTypedData(bytes: $0) } ?? NSNull()
            })
        case "openURL":
            if let string = args["url"] as? String, let url = URL(string: string) { NSWorkspace.shared.open(url) }
            result(nil)
        case "reveal":
            if let path = args["path"] as? String { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            result(nil)
        case "print", "pdf":
            guard let window = controller?.window else { return result("нет окна") }
            PagePrinter.start(html: args["html"] as? String ?? "", base: args["base"] as? String, title: args["title"] as? String ?? "",
                              destination: call.method == "pdf" ? args["path"] as? String : nil, window: window) { error in result(error) }
        case "textWidths":
            // Widths of a sample line in the system font as AppKit lays it out (with its size-specific tracking).
            let sample = args["sample"] as? String ?? ""
            let sizes = args["sizes"] as? [Double] ?? []
            result(sizes.map { size -> Double in
                let font = NSFont.systemFont(ofSize: size)
                return Double(NSAttributedString(string: sample, attributes: [.font: font]).size().width)
            })
        case "beep":
            NSSound.beep()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

enum Panels {
    static let markdownTypes: [UTType] = [UTType("net.daringfireball.markdown"), .plainText].compactMap { $0 }

    static func openPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = markdownTypes
        return panel
    }

    /// The system save panel as a sheet, starting in the document folder.
    static func save(in window: NSWindow, title: String, prompt: String?, name: String, directory: String?, fileExtension: String,
                     completion: @escaping FlutterResult) {
        let panel = NSSavePanel()
        if !title.isEmpty { panel.title = title }
        if let prompt { panel.prompt = prompt }
        panel.nameFieldStringValue = name
        if let type = UTType(filenameExtension: fileExtension) { panel.allowedContentTypes = [type] }
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        if let directory { panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true) }
        panel.beginSheetModal(for: window) { response in
            completion(response == .OK ? panel.url?.path : nil)
        }
    }
}

