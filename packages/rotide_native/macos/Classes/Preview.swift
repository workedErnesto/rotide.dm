import AppKit
import FlutterMacOS
import UniformTypeIdentifiers
import WebKit

/// The rendered page as a platform view. The page logic (what to load, scrolling, links) lives in Dart and is shared
/// with Windows; this side owns the WKWebView, its isolated script world, the local file scheme and the round corners.
final class PreviewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        let arguments = args as? [String: Any] ?? [:]
        return PreviewView(id: viewId, messenger: messenger, script: arguments["script"] as? String ?? "",
                           radius: arguments["radius"] as? Double ?? 10)
    }

    func createArgsCodec() -> (NSObjectProtocol & FlutterMessageCodec)? { FlutterStandardMessageCodec.sharedInstance() }
}

/// Hosts the web view and stops it from taking clicks while a menu drawn by Flutter lies over it.
final class PreviewView: NSView, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let web: WKWebView
    private let channel: FlutterMethodChannel
    var blocked = false

    init(id: Int64, messenger: FlutterBinaryMessenger, script: String, radius: Double) {
        web = WebPage.make(script: script)
        channel = FlutterMethodChannel(name: "rotide/preview/\(id)", binaryMessenger: messenger)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsMagnification = true
        web.setAccessibilityLabel("предпросмотр")
        web.configuration.userContentController.add(WeakMessages(self), contentWorld: WebPage.world, name: "rotide")
        web.frame = bounds
        web.autoresizingMask = [.width, .height]
        addSubview(web)
        channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    deinit {
        channel.setMethodCallHandler(nil)
        web.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { blocked ? nil : super.hitTest(point) }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "load":
            let base = WebPage.baseURL(for: args["base"] as? String)
            web.loadHTMLString(args["html"] as? String ?? "", baseURL: base)
            result(nil)
        case "eval":
            web.evaluateJavaScript(args["script"] as? String ?? "", in: nil, in: WebPage.world) { _ in }
            result(nil)
        case "zoom":
            web.pageZoom = args["value"] as? Double ?? 1
            result(nil)
        case "blocked":
            blocked = args["value"] as? Bool ?? false
            if blocked, window?.firstResponder === web || (window?.firstResponder as? NSView)?.isDescendant(of: web) == true {
                window?.makeFirstResponder(nil)
            }
            result(nil)
        case "background":
            if let value = args["color"] as? Int {
                web.underPageBackgroundColor = NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                                                       blue: CGFloat(value & 0xff) / 255, alpha: 1)
            }
            result(nil)
        case "focus":
            window?.makeFirstResponder(web)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        channel.invokeMethod("message", arguments: message.body)
    }

    /// The page itself is the only navigation; links go to Dart, which scrolls, opens a Markdown file or the browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType != .other || action.targetFrame?.isMainFrame == false, let url = action.request.url else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        channel.invokeMethod("navigate", arguments: ["url": url.absoluteString, "path": url.path, "fragment": url.fragment ?? NSNull()])
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            channel.invokeMethod("navigate", arguments: ["url": url.absoluteString, "path": url.path, "fragment": url.fragment ?? NSNull()])
        }
        return nil
    }
}

/// Shared setup of every page rotide.dm renders: the live preview and the offscreen pages for PDF and printing.
enum WebPage {
    static let scheme = "rotide-local"
    static let world = WKContentWorld.world(name: "rotide")

    static func make(script: String?) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(LocalFiles(), forURLScheme: scheme)
        configuration.suppressesIncrementalRendering = false
        if let script, !script.isEmpty {
            configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world))
        }
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    /// Relative links and images resolve against the document folder through `rotide-local:`, which serves any local
    /// file, so `../images/logo.png` works the way it does on GitHub.
    static func baseURL(for directory: String?) -> URL? {
        guard let directory else { return URL(string: "\(scheme):///") }
        var components = URLComponents(url: URL(fileURLWithPath: directory, isDirectory: true), resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        components?.host = nil
        return components?.url
    }
}

/// Serves local files to the page under `rotide-local:`. The page runs no scripts of its own, so reading a file only
/// ever shows it.
final class LocalFiles: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = url.path
        DispatchQueue.global(qos: .userInitiated).async {
            let file = URL(fileURLWithPath: path)
            let data = try? Data(contentsOf: file)
            let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            DispatchQueue.main.async {
                guard let data else { task.didFailWithError(URLError(.fileDoesNotExist)); return }
                task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
                task.didReceive(data)
                task.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// WKUserContentController keeps its handlers alive; the proxy lets the view go when Flutter disposes it.
private final class WeakMessages: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Prints the page or saves it as PDF from an offscreen web view with the light theme, so paper stays white.
final class PagePrinter: NSObject, WKNavigationDelegate {
    private static var active: Set<PagePrinter> = []
    private let web: WKWebView
    private let holder: NSWindow
    private let destination: URL?
    private weak var window: NSWindow?
    private let completion: (String?) -> Void
    private var temporary: URL?

    private init(destination: URL?, window: NSWindow, completion: @escaping (String?) -> Void) {
        web = WebPage.make(script: nil)
        // The web view lays out and paints only inside a window; this one is never shown.
        holder = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 820, height: 1100), styleMask: [.borderless], backing: .buffered, defer: false)
        holder.isReleasedWhenClosed = false
        holder.contentView = web
        holder.appearance = NSAppearance(named: .aqua)
        self.destination = destination
        self.window = window
        self.completion = completion
        super.init()
        web.navigationDelegate = self
    }

    static func start(html: String, base: String?, title: String, destination: String?, window: NSWindow, completion: @escaping (String?) -> Void) {
        let printer = PagePrinter(destination: destination.map { URL(fileURLWithPath: $0) }, window: window, completion: completion)
        active.insert(printer)
        printer.web.loadHTMLString(html, baseURL: WebPage.baseURL(for: base))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Remote images keep loading after the document finishes; give them a moment, as Safari does before printing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in run() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error.localizedDescription) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error.localizedDescription)
    }

    private func run() {
        guard let window else { finish(nil); return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.topMargin = 42; info.bottomMargin = 42; info.leftMargin = 48; info.rightMargin = 48
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        if destination != nil {
            // Print into a temporary file and move it over the destination only when it is complete.
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            self.temporary = temporary
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = temporary
        }
        let operation = web.printOperation(with: info)
        operation.showsPrintPanel = destination == nil
        operation.showsProgressPanel = false
        operation.view?.frame = web.bounds
        operation.jobTitle = window.title
        operation.runModal(for: window, delegate: self, didRun: #selector(printed(_:success:context:)), contextInfo: nil)
    }

    /// AppKit may report the end of a print operation on its own thread; everything after it runs on the main one.
    @objc private func printed(_ operation: NSPrintOperation, success: Bool, context: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { [self] in complete(success: success) }
    }

    private func complete(success: Bool) {
        guard let destination, let temporary else { finish(nil); return }
        guard success, FileManager.default.fileExists(atPath: temporary.path) else {
            try? FileManager.default.removeItem(at: temporary)
            finish(success ? "файл PDF не создан" : nil)
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            finish(nil)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            finish(error.localizedDescription)
        }
    }

    private func finish(_ error: String?) {
        completion(error)
        holder.contentView = nil
        holder.close()
        Self.active.remove(self)
    }
}
