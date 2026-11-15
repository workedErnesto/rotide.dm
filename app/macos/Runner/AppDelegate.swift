import Cocoa
import FlutterMacOS
import rotide_native

/// Forwards the application events to RotideApp, which keeps one Flutter engine per window.
@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    RotideApp.shared.registerPlugins = { controller in RegisterGeneratedPlugins(registry: controller) }
    RotideApp.shared.applicationWillFinishLaunching()
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    RotideApp.shared.applicationDidFinishLaunching()
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    RotideApp.shared.open(urls: urls)
  }

  override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    RotideApp.shared.dockMenu()
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    RotideApp.shared.shouldHandleReopen(hasVisibleWindows: flag)
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    RotideApp.shared.shouldTerminate()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }
}
