import AppKit
import SwiftUI
import UzzyCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, AppCommands {
    private var statusItem: NSStatusItem?
    /// Released on quit so AppKit does not `-close` the popover window.
    private var popover: NSPopover?
    private var eventMonitors: [Any] = []
    private let panelBounds = PanelBounds()
    private let realCore = UsageCore(
        claudeSessionReader: ClaudeCodeSessionReader(),
        codexSessionReader: CodexCLISessionReader(),
        cursorSessionReader: CursorSessionReader(),
        transport: URLSessionTransport(),
        clock: SystemClock(),
        initialMagnitude: QuotaMagnitude(
            rawValue: UserDefaults.standard.string(forKey: "displayMagnitude") ?? ""
        ) ?? .used,
        initialEnabledProviders: ProviderPreferences.enabledProviders(in: .standard),
        initialOrder: ProviderPreferences.order(in: .standard)
    )
    #if DEBUG
    /// A Debug build never asks GitHub. `-update <version>` offers that
    /// version instead, e.g. `-update 9.9.9`.
    private let updates = UpdateChecker(
        currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        transport: SingleAnswerTransport(
            UserDefaults.standard.string(forKey: "update").map { .latestRelease(tag: "v\($0)") } ?? .networkError
        ),
        clock: SystemClock(),
        isEnabled: UpdatePreferences.checksForUpdates(in: .standard)
    )
    #else
    private let updates = UpdateChecker(
        currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        transport: URLSessionTransport(),
        clock: SystemClock(),
        isEnabled: UpdatePreferences.checksForUpdates(in: .standard)
    )
    #endif
    private var settingsWindow: NSWindow?
    #if DEBUG
    private lazy var scenarios = ScenarioSwitch(realCore: realCore)
    #endif

    /// The core the panel shows.
    private var core: UsageCore {
        #if DEBUG
        scenarios.core
        #else
        realCore
        #endif
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        let popover = NSPopover()
        self.popover = popover
        #if DEBUG
        let content = PanelHostingController(rootView: ScenarioPanel(scenarios: scenarios, updates: updates, bounds: panelBounds, openSettings: { [weak self] in
            self?.showSettings(nil)
        }, downloadUpdate: { [weak self] in
            self?.downloadUpdate()
        }) { [weak self] scenario in
            guard let self else { return }
            Task { await self.scenarios.show(scenario, panelIsOpen: self.popover?.isShown == true) }
        })
        #else
        let content = PanelHostingController(rootView: PanelView(core: realCore, updates: updates, bounds: panelBounds, openSettings: { [weak self] in
            self?.showSettings(nil)
        }, downloadUpdate: { [weak self] in
            self?.downloadUpdate()
        }))
        #endif
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        // The app closes the panel itself: `.transient` misses clicks in other
        // apps for an accessory app, and races with the icon's own toggle.
        popover.behavior = .applicationDefined
        popover.delegate = self
        // Unset, a popover stays on vibrantLight: light mode never picks up
        // Aqua's glass, and dark mode never applies.
        adoptSystemAppearance()
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // A template image from the asset catalog, so it follows the menu bar's
        // appearance and highlight like the system's own items.
        let icon = NSImage(resource: .menuBarIcon)
        icon.accessibilityDescription = Format.appName
        item.button?.image = icon
        #if DEBUG
        // Tells a Debug build apart from an installed Release copy in the menu bar.
        // The menu bar ignores `contentTintColor`, so the icon is drawn in color.
        let debugIcon = NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect)
            NSColor.systemOrange.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        debugIcon.isTemplate = false
        debugIcon.accessibilityDescription = Format.appName
        item.button?.image = debugIcon
        #endif
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        // A display's resolution or scaling can change while the panel is open.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fitPanelToScreen),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        updates.start()

        #if DEBUG
        // `-scenario <id>` opens the panel on that scenario, e.g. `-scenario stale`.
        // The icon waits for it, so the real accounts are never read.
        if let id = UserDefaults.standard.string(forKey: "scenario"),
           let scenario = Scenario.all.first(where: { $0.id == id }) {
            item.button?.isEnabled = false
            Task {
                await scenarios.show(scenario, panelIsOpen: false)
                item.button?.isEnabled = true
                await statusItemPlaced()
                if !popover.isShown {
                    openPanel()
                }
            }
        }
        #endif
    }

    #if DEBUG
    /// The menu bar places the icon over the first moments after launch. Until
    /// then its window is empty or off screen, and a popover shown from it
    /// never appears, or appears in a corner of the screen. Placed means on a
    /// screen and still for a tenth of a second. Gives up after two seconds.
    private func statusItemPlaced() async {
        var lastFrame: NSRect?
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(100))
            guard let window = statusItem?.button?.window else { return }
            let frame = window.frame
            if !frame.isEmpty, window.screen != nil, frame == lastFrame { return }
            lastFrame = frame
        }
    }
    #endif

    @objc private func systemDidWake() {
        core.systemWoke()
    }

    @objc private func togglePanel() {
        if popover?.isShown == true {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let popover, let button = statusItem?.button else { return }
        fitPanelToScreen()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        watchWhileOpen()
        core.panelOpened()
    }

    /// Keeps the panel within the screen whose menu bar holds the icon, which
    /// changes when the icon is clicked on another display.
    @objc private func fitPanelToScreen() {
        guard let screen = statusItem?.button?.window?.screen ?? NSScreen.main else { return }
        panelBounds.maxHeight = screen.visibleFrame.height - PanelLayout.screenMargin
    }

    /// Closes the panel like a macOS menu: on Escape or on a click in another app.
    /// ⌘Q, ⌘, and ⌘W come from the main menu, in the panel as in Settings.
    private func watchWhileOpen() {
        let escapeKeyCode: UInt16 = 53
        if let keyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == escapeKeyCode else { return event }
            self?.closePanel()
            return nil
        }) {
            eventMonitors.append(keyDown)
        }
        // Clicks on the status item also arrive as global events; the icon
        // toggles the panel itself, so they are left to `togglePanel`.
        if let outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self, !isOnStatusItem(NSEvent.mouseLocation) else { return }
            closePanel()
        }) {
            eventMonitors.append(outsideClick)
        }
    }

    private func isOnStatusItem(_ screenPoint: NSPoint) -> Bool {
        guard let button = statusItem?.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(screenPoint)
    }

    /// Closes instantly, like a menu. While a close animation runs the popover
    /// still reports `isShown`, so a quick click on the icon would be lost.
    /// `close()` is required: `performClose` ends up sending `-close` to the
    /// popover's window, which the app does not own.
    private func closePanel() {
        guard let popover, popover.isShown else { return }
        popover.animates = false
        popover.close()
        popover.animates = true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        releasePopover()
        return .terminateNow
    }

    /// `close()` hides the panel but leaves its window in `NSApp.windows`.
    /// Quitting then sends that window `-close`. `_NSPopoverWindow` overrides
    /// `close` only to log that the app does not own it. `NSWindow`'s own
    /// implementation unregisters the window, so the sweep never reaches it.
    private func releasePopover() {
        guard let popover else { return }
        popover.animates = false
        let window = popover.contentViewController?.view.window
        if popover.isShown {
            popover.close()
        }
        if let window {
            closeSkippingPopoverOverride(window)
        }
        popover.contentViewController = nil
        self.popover = nil
    }

    private func closeSkippingPopoverOverride(_ window: NSWindow) {
        let sel = #selector(NSWindow.close)
        guard let method = class_getInstanceMethod(NSWindow.self, sel) else { return }
        typealias CloseIMP = @convention(c) (NSWindow, Selector) -> Void
        let close = unsafeBitCast(method_getImplementation(method), to: CloseIMP.self)
        close(window, sel)
    }

    /// Brings the one Settings window forward, creating it the first time.
    /// Opened from the menu bar, the app is not active and macOS declines the
    /// cooperative `activate()`, so an open Settings window stays behind the
    /// frontmost app without focus; activation is forced instead. The panel
    /// closes only after Settings is key, so the app never lacks a key window.
    @objc func showSettings(_ sender: Any?) {
        core.panelClosed()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: 0),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = Format.current.settings
            let content = NSHostingController(rootView: SettingsView(
                setProviderEnabled: { [weak self] provider, enabled in self?.setProviderEnabled(enabled, for: provider) },
                setProviderOrder: { [weak self] order in self?.setProviderOrder(order) },
                setUpdateChecks: { [weak self] enabled in self?.updates.setEnabled(enabled) }
            ))
            // The window takes the form's height, so no row is clipped.
            content.sizingOptions = [.preferredContentSize]
            window.contentViewController = content
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        closePanel()
    }

    /// Hands the latest `Uzzy.dmg` to the browser, which downloads it, and
    /// gets the panel out of its way.
    private func downloadUpdate() {
        NSWorkspace.shared.open(UpdateChecker.download)
        closePanel()
    }

    /// ⌘W closes the panel like Escape, or else the key window, such as
    /// Settings, through its own close button's action.
    @objc func closeWindow(_ sender: Any?) {
        if popover?.isShown == true {
            closePanel()
        } else {
            NSApp.keyWindow?.performClose(sender)
        }
    }

    private func setProviderEnabled(_ enabled: Bool, for provider: Provider) {
        realCore.setEnabled(enabled, for: provider)
        #if DEBUG
        if scenarios.core !== realCore {
            scenarios.core.setEnabled(enabled, for: provider)
        }
        #endif
    }

    private func setProviderOrder(_ order: [Provider]) {
        realCore.setOrder(order)
        #if DEBUG
        if scenarios.core !== realCore {
            scenarios.core.setOrder(order)
        }
        #endif
    }

    func popoverWillShow(_ notification: Notification) {
        adoptSystemAppearance()
    }

    func popoverDidClose(_ notification: Notification) {
        core.panelClosed()
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    /// Aqua or Dark Aqua, including their high-contrast variants. `vibrantLight`
    /// is the popover default and does not follow the system.
    private func adoptSystemAppearance() {
        let names: [NSAppearance.Name] = [
            .aqua,
            .darkAqua,
            .accessibilityHighContrastAqua,
            .accessibilityHighContrastDarkAqua,
        ]
        if let name = NSApp.effectiveAppearance.bestMatch(from: names) {
            popover?.appearance = NSAppearance(named: name)
        } else {
            popover?.appearance = NSApp.effectiveAppearance
        }
    }

    @objc private func systemAppearanceChanged() {
        adoptSystemAppearance()
    }
}

/// Hosts the panel without painting over the Liquid Glass the popover draws
/// behind it. The default hosting view is opaque, so light mode reads as a
/// flat gray slab and the desktop never shows through.
private final class PanelHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        // SwiftUI fills the hosting view. Clearing that fill is what lets the
        // popover's own glass show through; the layer is left alone so the
        // system highlight is not blown out.
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
    }
}
