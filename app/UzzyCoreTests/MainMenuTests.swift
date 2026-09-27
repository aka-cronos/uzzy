import AppKit
import Testing

/// The standard shortcuts every Uzzy window answers to. This target compiles
/// `Uzzy/MainMenu.swift` and `Uzzy/Format.swift` from the app.
@MainActor
struct MainMenuTests {
    /// Each plain ⌘ shortcut: its key, the command it names in the menu's
    /// language, and the action it sends up the responder chain.
    @Test(arguments: [
        (format: Format.spanish, key: "q", title: "Salir de \(Format.appName)", action: "terminate:"),
        (format: Format.spanish, key: ",", title: "Ajustes…", action: "showSettings:"),
        (format: Format.spanish, key: "w", title: "Cerrar ventana", action: "closeWindow:"),
        (format: Format.english, key: "q", title: "Quit \(Format.appName)", action: "terminate:"),
        (format: Format.english, key: ",", title: "Settings…", action: "showSettings:"),
        (format: Format.english, key: "w", title: "Close Window", action: "closeWindow:"),
    ])
    func commandShortcutSendsItsActionToTheResponderChain(
        shortcut: (format: Format, key: String, title: String, action: String)
    ) throws {
        let item = try #require(item(forCommand: shortcut.key, in: MainMenu.make(format: shortcut.format)))
        #expect(item.title == shortcut.title)
        #expect(item.action.map(NSStringFromSelector) == shortcut.action)
        #expect(item.target == nil)
    }

    @Test func theMenusAreNamedInTheMenusLanguage() {
        #expect(MainMenu.make(format: .spanish).items.map(\.title) == [Format.appName, "Archivo"])
        #expect(MainMenu.make(format: .english).items.map(\.title) == [Format.appName, "File"])
    }

    @Test func onlyTheStandardShortcutsAreClaimed() {
        let shortcuts = allItems(in: MainMenu.make()).filter { !$0.keyEquivalent.isEmpty }.map(\.keyEquivalent)
        #expect(shortcuts.sorted() == [",", "q", "w"])
    }

    /// The item a plain ⌘ + `key` triggers, searched through every submenu.
    private func item(forCommand key: String, in menu: NSMenu) -> NSMenuItem? {
        allItems(in: menu).first {
            $0.keyEquivalent == key && $0.keyEquivalentModifierMask == .command
        }
    }

    /// Every item in `menu` and its submenus, depth first.
    private func allItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in [item] + (item.submenu.map(allItems) ?? []) }
    }
}
