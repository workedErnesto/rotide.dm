import AppKit
import FlutterMacOS
import UniformTypeIdentifiers

/// One window with its own Flutter engine: the start window or a document. A transparent title bar over the shell,
/// the behind-window blur under the Flutter view (the document card is drawn opaque by Flutter), the standard window
/// buttons on the centre line of the 44 pt top bar, and a fade on first show once Flutter has drawn its first frame.
final class RotideWindowController: NSWindowController, NSWindowDelegate {
    enum Kind: String { case start, document }

    static let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    static let bar: CGFloat = 44
    static let lightsX: CGFloat = 14
    static let lightsStep: CGFloat = 20

    let kind: Kind
    private(set) var path: String?
    let flutter: FlutterViewController
    let effect = NSVisualEffectView()
    var channel: FlutterMethodChannel?

    /// Menu state reported by the document: mode, outline, export in progress, a dialog on screen.
    var state: [String: Any] = [:]
    private var closeApproved = false
    private var asking = false
    private var shown = false
    private var closed = false
    private var placing = false
    private var placementPending = false

    init(kind: Kind, path: String?) {
        self.kind = kind
        self.path = path
        let project = FlutterDartProject()
        project.dartEntrypointArguments = [kind.rawValue, path ?? ""]
        flutter = FlutterViewController(project: project)
        flutter.backgroundColor = .clear

        let window: NSWindow
        let contentSize: NSSize
        switch kind {
        case .start:
            // The SwiftUI start view extended 28 pt into the title bar area: 520 + 28.
            contentSize = NSSize(width: 600, height: 548)
            window = RotideWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        case .document:
            let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
            let size = NSSize(width: min(1320, max(860, visible.width * 0.72)), height: min(980, max(620, visible.height * 0.86)))
            contentSize = size
            window = RotideWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.minSize = NSSize(width: 560, height: 420)
            window.collectionBehavior = [.fullScreenPrimary]
        }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // A clear, non-opaque window lets the behind-window blur of the shell reach the desktop.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.title = path.map { ($0 as NSString).lastPathComponent } ?? "rotide.dm"
        window.tabbingMode = .disallowed
        super.init(window: window)

        let content = ContentController(flutter: flutter, effect: effect, acceptsFiles: kind == .start)
        // Setting the content controller sizes the window to its view; give it back the intended content size.
        window.contentViewController = content
        window.setContentSize(contentSize)
        window.delegate = self
        switch kind {
        case .start:
            window.center()
        case .document:
            window.setFrameAutosaveName("document-window")
            if RotideApp.shared.documents.count > 0 { window.center() }
            for type in Self.buttons {
                guard let button = window.standardWindowButton(type) else { continue }
                button.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(buttonFrameChanged), name: NSView.frameDidChangeNotification, object: button)
            }
            placeWindowButtons()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    /// Starts the engine; the window appears once Dart reports its first frame (or after a safety delay).
    func load() {
        RotideApp.shared.registerPlugins?(flutter)
        // Each engine claims the system quit event for itself; a closed window's engine would swallow it.
        RotideApp.shared.claimQuitEvent()
        DispatchQueue.main.async { RotideApp.shared.claimQuitEvent() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.reveal() }
    }

    func send(_ method: String, _ arguments: Any?) {
        channel?.invokeMethod(method, arguments: arguments)
    }

    // MARK: Showing

    func reveal() {
        guard let window, !shown, !closed else { return }
        shown = true
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        if kind == .document { placeWindowButtons() }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? 0.15 : 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func setFrost(_ enabled: Bool) { effect.isHidden = !enabled }

    func setDocument(path: String?, title: String, edited: Bool) {
        self.path = path
        window?.title = title
        window?.isDocumentEdited = edited
        if let path { window?.representedURL = URL(fileURLWithPath: path) } else { window?.representedURL = nil }
    }

    // MARK: Closing

    /// Asks Dart whether the document may close (it shows the save question when needed).
    func askToClose(_ reply: @escaping (Bool) -> Void) {
        guard kind == .document, let channel else { reply(true); return }
        NSApp.unhide(nil)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        channel.invokeMethod("shouldClose", arguments: nil) { [weak self] result in
            let allowed = (result as? Bool) ?? true
            if allowed { self?.closeApproved = true }
            reply(allowed)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closeApproved || kind == .start { return true }
        guard !asking else { return false }
        asking = true
        askToClose { [weak self] allowed in
            self?.asking = false
            if allowed { self?.window?.close() }
        }
        return false
    }

    func closeNow() {
        closeApproved = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        closed = true
        NotificationCenter.default.removeObserver(self)
        channel?.setMethodCallHandler(nil)
        channel = nil
        RotideApp.shared.removed(self)
        // Let the window finish closing before the engine goes.
        DispatchQueue.main.async { [flutter] in
            flutter.engine.shutDownEngine()
        }
    }

    // MARK: Chrome

    @objc private func buttonFrameChanged() {
        guard !placing, !placementPending else { return }
        placementPending = true
        DispatchQueue.main.async { [weak self] in
            self?.placementPending = false
            self?.placeWindowButtons()
        }
    }

    /// The window buttons on the centre line of the top bar, as in mica.
    func placeWindowButtons() {
        guard kind == .document, let window, let content = window.contentView, !window.styleMask.contains(.fullScreen), !placing else { return }
        placing = true
        defer { placing = false }
        for (index, type) in Self.buttons.enumerated() {
            guard let button = window.standardWindowButton(type), let bar = button.superview else { continue }
            let size = button.frame.size
            let center = NSPoint(x: Self.lightsX + CGFloat(index) * Self.lightsStep + size.width / 2,
                                 y: content.isFlipped ? Self.bar / 2 : content.bounds.height - Self.bar / 2)
            let inBar = bar.convert(center, from: content)
            let target = NSPoint(x: inBar.x - size.width / 2, y: inBar.y - size.height / 2)
            if button.frame.origin != target { button.setFrameOrigin(target) }
        }
    }

    /// Empty chrome moves the window like a title bar; a double click zooms it, as the system setting says.
    func dragWindow() {
        guard let window, let event = NSApp.currentEvent else { return }
        guard [.leftMouseDown, .leftMouseDragged].contains(event.type) else { return }
        window.performDrag(with: event)
        // The drag loop swallows the mouse-up; tell Flutter the button is up again so its gestures do not hang.
        if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: window.mouseLocationOutsideOfEventStream, modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 0) {
            flutter.view.mouseUp(with: up)
        }
    }

    func titleBarDoubleClick() {
        guard let window else { return }
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        if action == "Minimize" { window.performMiniaturize(nil) } else if action != "None" { window.performZoom(nil) }
    }

    func windowDidResize(_ notification: Notification) { placeWindowButtons() }
    func windowDidEnterFullScreen(_ notification: Notification) { send("fullScreen", true) }
    func windowDidExitFullScreen(_ notification: Notification) {
        send("fullScreen", false)
        placeWindowButtons()
    }
    func windowDidBecomeKey(_ notification: Notification) { send("key", true) }
    func windowDidResignKey(_ notification: Notification) { send("key", false) }
}

/// The window content: the behind-window blur with the Flutter view on top of it.
private final class ContentController: NSViewController {
    let flutter: FlutterViewController
    let effect: NSVisualEffectView
    let acceptsFiles: Bool

    init(flutter: FlutterViewController, effect: NSVisualEffectView, acceptsFiles: Bool) {
        self.flutter = flutter
        self.effect = effect
        self.acceptsFiles = acceptsFiles
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func loadView() {
        let container = DropView(frame: NSRect(x: 0, y: 0, width: 600, height: 520))
        container.wantsLayer = true
        if acceptsFiles { container.registerForDraggedTypes([.fileURL]) }
        // Active in background windows too, so the material does not flip to a flat fill when another app has focus.
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.frame = container.bounds
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)
        addChild(flutter)
        flutter.view.frame = container.bounds
        flutter.view.autoresizingMask = [.width, .height]
        container.addSubview(flutter.view)
        Self.forwardClicksToFlutter()
        objc_setAssociatedObject(flutter.view, &Self.controllerKey, flutter, .OBJC_ASSOCIATION_ASSIGN)
        view = container
    }

    private static var clicksForwarded = false
    private static var controllerKey = 0

    /// Hover reaches Flutter through its tracking area, but a press stopped at FlutterViewWrapper: the wrapper is meant to
    /// pass mouse down and up to its controller and does not when the view sits under our own container, so no button
    /// ever received a click. The wrapper's two handlers now hand the event to the controller that owns the view.
    private static func forwardClicksToFlutter() {
        guard !clicksForwarded, let wrapper = NSClassFromString("FlutterViewWrapper") else { return }
        clicksForwarded = true
        let handlers: [(String, (FlutterViewController, NSEvent) -> Void)] = [
            ("mouseDown:", { $0.mouseDown(with: $1) }),
            ("mouseUp:", { $0.mouseUp(with: $1) }),
        ]
        for (name, forward) in handlers {
            guard let method = class_getInstanceMethod(wrapper, NSSelectorFromString(name)) else { continue }
            let block: @convention(block) (NSView, NSEvent) -> Void = { view, event in
                if let controller = objc_getAssociatedObject(view, &ContentController.controllerKey) as? FlutterViewController { forward(controller, event) }
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }
}

/// Takes Markdown, text, Word and RTF files dragged onto the start window and opens them; Dart draws the dashed target.
private final class DropView: NSView {
    private static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext", "txt", "text", "docx", "rtf"]

    private func files(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { url in
            Self.extensions.contains(url.pathExtension.lowercased()) || UTType(filenameExtension: url.pathExtension)?.conforms(to: .plainText) == true
        }
    }

    private var controller: RotideWindowController? { window?.windowController as? RotideWindowController }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !files(sender).isEmpty else { return [] }
        controller?.send("dropping", true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { controller?.send("dropping", false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        controller?.send("dropping", false)
        let urls = files(sender)
        guard !urls.isEmpty else { return false }
        DispatchQueue.main.async { urls.forEach { RotideApp.shared.openDocument($0.path) } }
        return true
    }
}

/// Sends the menu's key equivalents to the menu before the Flutter view sees them: while a Flutter text field has
/// focus its text input client would otherwise swallow them. Text editing keys stay with Flutter.
final class RotideWindow: NSWindow {
    private static let editingKeys: Set<String> = ["a", "c", "v", "x", "z"]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let editing = modifiers.contains(.command) && !modifiers.contains(.control) && Self.editingKeys.contains(key)
        if !editing, modifiers.contains(.command) || modifiers.contains(.control), NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
