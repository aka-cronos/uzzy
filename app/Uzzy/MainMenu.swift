import AppKit

/// The app commands the main menu sends up the responder chain. The app
/// delegate, at the end of that chain, implements them, so they work from any
/// window.
@MainActor @objc protocol AppCommands {
    /// Brings the one Settings window forward (⌘,).
    func showSettings(_ sender: Any?)
    /// Closes the panel if it is open, otherwise the key window (⌘W). No window
    /// implements this selector, so it always reaches the app delegate, even
    /// from the panel's window, which the app must not send `-performClose:`.
    func closeWindow(_ sender: Any?)
}

/// The app's main menu. A menu bar app never shows it, but AppKit still matches
/// its key equivalents in every window, so the standard shortcuts work in the
/// panel and in Settings without intercepting the keyboard.
enum MainMenu {
    /// Builds the menu for `NSApp.mainMenu`: the app menu with Settings and
    /// Quit, and a File menu with Close Window.
    @MainActor static func make() -> NSMenu {
        // Every action has a nil target, so the responder chain delivers and
        // validates it: the key window first, then the app and its delegate.
        let appMenu = NSMenu(title: Format.appName)
        appMenu.addItem(withTitle: Format.openSettings, action: #selector(AppCommands.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: Format.quitApp, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenu = NSMenu(title: "Archivo")
        fileMenu.addItem(withTitle: Format.closeWindow, action: #selector(AppCommands.closeWindow(_:)), keyEquivalent: "w")

        let mainMenu = NSMenu()
        for submenu in [appMenu, fileMenu] {
            mainMenu.addItem(withTitle: submenu.title, action: nil, keyEquivalent: "").submenu = submenu
        }
        return mainMenu
    }
}
