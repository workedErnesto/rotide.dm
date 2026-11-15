import AppKit

/// The menu bar, in Russian and in rotide.dm's lowercase style. Text editing commands go through the responder chain
/// (the Flutter text field and the web page both answer them); document and view commands go to the key window's Dart.
enum MainMenu {
    static func make() -> NSMenu {
        let bar = NSMenu()
        bar.addItem(submenu(app()))
        bar.addItem(submenu(file()))
        bar.addItem(submenu(edit()))
        bar.addItem(submenu(view()))
        let window = windowMenu()
        bar.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "справка")
        bar.addItem(submenu(help))
        NSApp.helpMenu = help
        return bar
    }

    private static var written: [ObjectIdentifier: String] = [:]

    /// The menu text in the letter case the user chose: lowercase as written, or raised at the first letter. Window
    /// titles and recent files are the user's own names and keep their spelling.
    static func apply(capitalized: Bool, in menu: NSMenu? = NSApp.mainMenu) {
        guard let menu else { return }
        for item in menu.items where !item.isSeparatorItem {
            if item.representedObject is NSWindow || item.action == #selector(NSWindow.makeKeyAndOrderFront(_:)) { continue }
            let key = ObjectIdentifier(item)
            let original = written[key] ?? item.title
            written[key] = original
            let title = capitalized && !original.hasPrefix("rotide.dm") ? original.prefix(1).uppercased() + original.dropFirst() : original
            item.title = title
            guard let sub = item.submenu, sub.delegate !== RecentMenu.shared else { continue }
            if menu === NSApp.mainMenu { sub.title = title }
            apply(capitalized: capitalized, in: sub)
        }
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command,
                             target: AnyObject? = nil, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        item.tag = tag
        return item
    }

    /// A command handled by the key window's Dart.
    private static func command(_ title: String, _ name: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let entry = item(title, #selector(DocumentCommands.run(_:)), key, modifiers, target: DocumentCommands.shared, tag: tag)
        entry.identifier = NSUserInterfaceItemIdentifier(name)
        return entry
    }

    private static func app() -> NSMenu {
        let menu = NSMenu(title: "rotide.dm")
        menu.addItem(item("о rotide.dm", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""))
        menu.addItem(item("настройки…", #selector(RotideApp.showSettings), ",", target: RotideApp.shared))
        menu.addItem(.separator())
        let services = NSMenu(title: "службы")
        menu.addItem(submenu(services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("скрыть rotide.dm", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("скрыть остальные", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("показать все", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("завершить rotide.dm", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func file() -> NSMenu {
        let menu = NSMenu(title: "файл")
        menu.addItem(item("новый", #selector(RotideApp.newDocument), "n", target: RotideApp.shared))
        menu.addItem(item("открыть…", #selector(RotideApp.openPanel), "o", target: RotideApp.shared))
        let recent = NSMenu(title: "открыть недавние")
        recent.autoenablesItems = false
        recent.delegate = RecentMenu.shared
        menu.addItem(submenu(recent))
        menu.addItem(item("начальное окно", #selector(RotideApp.showStart), "0", [.command, .shift], target: RotideApp.shared))
        menu.addItem(.separator())
        menu.addItem(item("закрыть", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(command("сохранить", "save", "s"))
        menu.addItem(command("сохранить как…", "saveAs", "s", [.command, .shift]))
        menu.addItem(command("вернуть к сохранённому", "revert"))
        menu.addItem(.separator())
        let export = NSMenu(title: "экспортировать как")
        for (index, title) in ["веб-страница HTML", "документ PDF", "документ Word", "текст RTF", "простой текст"].enumerated() {
            export.addItem(command(title + "…", "export", index == 0 ? "e" : "", [.command, .shift], tag: index))
        }
        menu.addItem(submenu(export))
        menu.addItem(command("меню экспорта", "exportMenu"))
        menu.addItem(.separator())
        menu.addItem(command("напечатать…", "print", "p"))
        return menu
    }

    private static func edit() -> NSMenu {
        let menu = NSMenu(title: "правка")
        menu.addItem(item("отменить", Selector(("undo:")), "z"))
        menu.addItem(item("повторить", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("вырезать", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("скопировать", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("вставить", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("вставить без форматирования", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]))
        menu.addItem(item("выбрать все", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        let find = NSMenu(title: "найти")
        find.addItem(command("найти…", "find", "f"))
        find.addItem(command("найти и заменить…", "replace", "f", [.command, .option]))
        find.addItem(command("найти далее", "findNext", "g"))
        find.addItem(command("найти ранее", "findPrevious", "g", [.command, .shift]))
        find.addItem(command("искать выделенное", "findSelection", "e"))
        menu.addItem(submenu(find))
        return menu
    }

    private static func view() -> NSMenu {
        let menu = NSMenu(title: "вид")
        menu.addItem(command("чтение", "mode", "1", tag: 0))
        menu.addItem(command("правка", "mode", "2", tag: 1))
        menu.addItem(.separator())
        menu.addItem(command("содержание", "sidebar", "s", [.command, .control]))
        menu.addItem(.separator())
        menu.addItem(command("увеличить", "zoomIn", "+"))
        menu.addItem(command("уменьшить", "zoomOut", "-"))
        menu.addItem(command("реальный размер", "zoomReset", "0"))
        menu.addItem(.separator())
        menu.addItem(item("во весь экран", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "окно")
        menu.addItem(item("свернуть", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("изменить масштаб", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("все окна на передний план", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}

/// Document and view commands for the key window, validated against the state its Dart reported.
final class DocumentCommands: NSObject, NSMenuItemValidation {
    static let shared = DocumentCommands()

    private var target: RotideWindowController? {
        guard let controller = RotideApp.shared.keyController, controller.kind == .document else { return nil }
        return controller
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let target, let name = menuItem.identifier?.rawValue else { return false }
        let state = target.state
        if state["dialog"] as? Bool == true { return false }
        switch name {
        case "mode":
            menuItem.state = (state["mode"] as? Int) == menuItem.tag ? .on : .off
        case "sidebar":
            menuItem.state = (state["sidebar"] as? Bool) == true ? .on : .off
        case "export", "exportMenu":
            return state["exporting"] as? Bool != true
        case "revert":
            return state["canRevert"] as? Bool == true
        case "find", "replace", "findNext", "findPrevious", "findSelection":
            return (state["mode"] as? Int) == 1
        default:
            break
        }
        return true
    }

    @objc func run(_ sender: NSMenuItem) {
        guard let name = sender.identifier?.rawValue else { return }
        target?.send("menu", ["command": name, "tag": sender.tag])
    }
}
