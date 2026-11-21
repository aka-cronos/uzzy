import AppKit
import Observation
import SwiftUI

/// A pane of the Settings window, picked from its preference toolbar.
nonisolated enum SettingsTab: String, CaseIterable, Sendable {
    case general
    case providers
    case notifications

    var toolbarIdentifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue) }

    @MainActor var title: String {
        switch self {
        case .general: Format.current.generalTab
        case .providers: Format.current.providersTab
        case .notifications: Format.current.notificationsTab
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .providers: "sparkles"
        case .notifications: "bell"
        }
    }
}

/// The tab Settings shows. It lives as long as the window, which is kept
/// after closing, so a reopened Settings returns to the last tab of the
/// session; a new launch starts on General.
@MainActor @Observable final class SettingsNavigation {
    var tab: SettingsTab = .general
}

/// The Settings window: a preference toolbar with one selectable item per
/// tab over the tab's grouped form. The window keeps the form's width and
/// takes each tab's height, growing or shrinking from its bottom edge so the
/// title bar and the toolbar never move.
@MainActor final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private let navigation = SettingsNavigation()
    /// The tab of the height last applied, to tell a tab switch, which
    /// animates, from a row appearing or disappearing inside a tab.
    private var sizedTab: SettingsTab

    /// `content` builds the form for the tab `navigation` holds, and calls
    /// back with the tab and the height it lays out at.
    init(content: (SettingsNavigation, @escaping @MainActor (SettingsTab, CGFloat) -> Void) -> SettingsView) {
        sizedTab = navigation.tab
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: 0),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        // The title stays "Settings" on every tab.
        window.title = Format.current.settings
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let toolbar = NSToolbar(identifier: "Settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = Set(SettingsTab.allCases.map(\.toolbarIdentifier))
        toolbar.selectedItemIdentifier = navigation.tab.toolbarIdentifier
        window.toolbar = toolbar

        let relay = HeightRelay()
        let hostingView = NSHostingView(rootView: content(navigation) { tab, height in relay.action?(tab, height) })
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        let container = FlippedView()
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container
        // The first size is set before the window is centered, never animated.
        window.setContentSize(NSSize(width: SettingsView.width, height: hostingView.fittingSize.height))
        window.center()
        relay.action = { [weak self] tab, height in self?.fit(height: height, for: tab) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Gives the window `height` of content, keeping its top edge and its
    /// left edge where they are. A tab switch animates unless Reduce Motion
    /// is on; a row appearing or disappearing in the same tab does not.
    private func fit(height: CGFloat, for tab: SettingsTab) {
        defer { sizedTab = tab }
        guard let window else { return }
        let size = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: height)).size
        let current = window.frame
        guard abs(current.height - size.height) >= 0.5 || abs(current.width - size.width) >= 0.5 else { return }
        let frame = NSRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height)
        let animate = tab != sizedTab
            && window.isVisible
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true, animate: false)
        }
    }

    @objc private func selectTab(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        // Accessibility and keyboard actions fire the item's action without
        // updating the toolbar's own selection highlight, so sync it here.
        window?.toolbar?.selectedItemIdentifier = tab.toolbarIdentifier
        navigation.tab = tab
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }
}

/// Hands the form's height to the controller, which only exists once the
/// form it hosts is built.
@MainActor private final class HeightRelay {
    var action: ((SettingsTab, CGFloat) -> Void)?
}

/// Top-left origin container so resizing the window from its bottom edge
/// keeps the SwiftUI form anchored cleanly beneath the toolbar.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
