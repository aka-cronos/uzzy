import AppKit
import Testing

/// The standard shortcuts every Uzzy window answers to. This target compiles
/// `Uzzy/MainMenu.swift` and `Uzzy/Format.swift` from the app.
@MainActor
struct MainMenuTests {
    let menu = MainMenu.make()

    /// Each plain ⌘ shortcut: its key, the command it names, and the action it
    /// sends up the responder chain.
    @Test(arguments: [
        (key: "q", title: Format.quitApp, action: "terminate:"),
        (key: ",", title: "Ajustes…", action: "showSettings:"),
        (key: "w", title: "Cerrar ventana", action: "closeWindow:"),
    ])
    func commandShortcutSendsItsActionToTheResponderChain(
        shortcut: (key: String, title: String, action: String)
    ) throws {
        let item = try #require(item(forCommand: shortcut.key))
        #expect(item.title == shortcut.title)
        #expect(item.action.map(NSStringFromSelector) == shortcut.action)
        #expect(item.target == nil)
    }

    @Test func onlyTheStandardShortcutsAreClaimed() {
        let shortcuts = allItems(in: menu).filter { !$0.keyEquivalent.isEmpty }.map(\.keyEquivalent)
        #expect(shortcuts.sorted() == [",", "q", "w"])
    }

    /// The item a plain ⌘ + `key` triggers, searched through every submenu.
    private func item(forCommand key: String) -> NSMenuItem? {
        allItems(in: menu).first {
            $0.keyEquivalent == key && $0.keyEquivalentModifierMask == .command
        }
    }

    /// Every item in `menu` and its submenus, depth first.
    private func allItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in [item] + (item.submenu.map(allItems) ?? []) }
    }
}
