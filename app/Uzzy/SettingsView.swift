import SwiftUI
import UzzyCore

/// The Settings window's content: the selected tab's native grouped form,
/// where each row has a title, a short description and a trailing control,
/// as in System Settings.
struct SettingsView: View {
    static let width: CGFloat = 480

    /// The real accounts' core, which holds the consent to read Cursor's key.
    let core: UsageCore
    /// Asks for and reports macOS's permission to notify.
    let notifier: Notifier
    let setProviderEnabled: @MainActor (Provider, Bool) -> Void
    let setProviderOrder: @MainActor ([Provider]) -> Void
    let setUpdateChecks: @MainActor (Bool) -> Void
    /// The tab the window's toolbar selected.
    let navigation: SettingsNavigation
    /// Reports the tab and the height it lays out at, which the window takes.
    let heightChanged: @MainActor (SettingsTab, CGFloat) -> Void
    @AppStorage("displayMagnitude") private var selectedMagnitude: QuotaMagnitude = .used
    @AppStorage(CountdownStyle.key) private var countdownStyle: CountdownStyle = .simple
    @AppStorage("showBankedResets") private var showBankedResets = true
    @AppStorage(ProviderPreferences.claudeKey) private var showClaude = true
    @AppStorage(ProviderPreferences.codexKey) private var showCodex = true
    @AppStorage(ProviderPreferences.cursorKey) private var showCursor = true
    @AppStorage(ProviderPreferences.antigravityKey) private var showAntigravity = true
    @AppStorage(UpdatePreferences.checkKey) private var checkForUpdates = true
    @AppStorage(NotificationPreferences.backgroundRefreshKey) private var backgroundRefresh = false
    @AppStorage(NotificationPreferences.intervalKey) private var intervalMinutes = NotificationPreferences.defaultIntervalMinutes
    @AppStorage(NotificationPreferences.nearLimitKey) private var alertNearLimit = false
    @AppStorage(NotificationPreferences.thresholdKey) private var alertThreshold = NotificationPreferences.defaultThreshold
    @AppStorage(NotificationPreferences.limitReachedKey) private var alertLimitReached = false
    @AppStorage(NotificationPreferences.limitResetKey) private var alertLimitReset = false
    /// `@AppStorage` cannot hold a list, so the order is saved by hand.
    @State private var order = ProviderPreferences.order(in: .standard)
    @State private var isConfirmingRevocation = false
    /// The steps to remove Uzzy from the keychain item, after the consent
    /// is withdrawn: macOS may still trust the app with the key.
    @State private var isShowingKeychainSteps = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch navigation.tab {
            case .general:
                general
            case .providers:
                providers
            case .notifications:
                notifications
            }
        }
        .id(navigation.tab)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        // The window takes the tab's height, so no row is clipped. The tab
        // rides along so a switch reports even between equal heights.
        .onGeometryChange(for: TabHeight.self) { [tab = navigation.tab] in TabHeight(tab: tab, height: $0.size.height) } action: { size in
            heightChanged(size.tab, size.height)
        }
        // Keep the form pinned to the top edge while the window animates
        // between tab heights, rather than centering it in the previous height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: showClaude) { _, enabled in setProviderEnabled(.claude, enabled) }
        .onChange(of: showCodex) { _, enabled in setProviderEnabled(.codex, enabled) }
        .onChange(of: showAntigravity) { _, enabled in setProviderEnabled(.antigravity, enabled) }
        .onChange(of: showCursor) { _, enabled in
            let hadAccess = core.isCursorAccessGranted
            setProviderEnabled(.cursor, enabled)
            if !enabled, hadAccess { isShowingKeychainSteps = true }
        }
        .onChange(of: checkForUpdates) { _, enabled in setUpdateChecks(enabled) }
        .onChange(of: backgroundRefresh) { _, isOn in core.setBackgroundRefresh(isOn) }
        .onChange(of: intervalMinutes) { _, minutes in core.setBackgroundInterval(TimeInterval(minutes * 60)) }
        .onChange(of: alertNearLimit) { _, isOn in alertsChanged(turningOn: isOn) }
        .onChange(of: alertThreshold) { _, _ in alertsChanged(turningOn: false) }
        .onChange(of: alertLimitReached) { _, isOn in alertsChanged(turningOn: isOn) }
        .onChange(of: alertLimitReset) { _, isOn in alertsChanged(turningOn: isOn) }
        .onChange(of: navigation.tab) { _, tab in
            if tab == .notifications { notifier.refreshAuthorization() }
        }
        .onAppear { notifier.refreshAuthorization() }
        // On the window rather than the Providers tab: turning Cursor off
        // shows the steps, and they must not depend on the tab staying put.
        .alert("Revoke access to Cursor's key?", isPresented: $isConfirmingRevocation) {
            Button("Revoke", role: .destructive) {
                core.revokeCursorAccess()
                isShowingKeychainSteps = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(Format.appName) will stop reading the Cursor session until you allow it again on the Cursor card.")
        }
        .alert("Remove \(Format.appName) from the keychain item", isPresented: $isShowingKeychainSteps) {
            Button("OK") {}
        } message: {
            Text("\(Format.appName) no longer reads Cursor's key. If you chose Always Allow, macOS still lets it, and only you can remove that: open Keychain Access, search for \"Cursor Safe Storage\" (account Cursor), open it, and in Access Control remove \(Format.appName), then Save Changes.")
        }
    }

    /// Turning an alert on is the only moment macOS's permission is asked.
    private func alertsChanged(turningOn: Bool) {
        core.setAlerts(AlertSettings(
            nearLimit: alertNearLimit,
            threshold: Double(alertThreshold),
            limitReached: alertLimitReached,
            limitReset: alertLimitReset
        ))
        if turningOn { notifier.requestAuthorization() }
    }

    /// A tab's grouped form, at its full height: the window sizes to it
    /// instead of scrolling.
    private func tabForm(@ViewBuilder _ sections: () -> some View) -> some View {
        Form(content: sections)
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The display, reset and update settings, over the app's version.
    private var general: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabForm {
                Section("Usage limits") {
                    let title = String(localized: "Percentage on the cards")
                    let description = String(localized: "Shows how much of each limit you've used, or how much you have left until it resets.")
                    SettingsRow(title: title, description: description) {
                        // The hidden title still names the control for VoiceOver.
                        Picker(title, selection: $selectedMagnitude) {
                            // The same words as the suffix after each card's figure.
                            Text(Format.current.name(of: QuotaMagnitude.used).localizedCapitalized).tag(QuotaMagnitude.used)
                            Text(Format.current.name(of: QuotaMagnitude.remaining).localizedCapitalized).tag(QuotaMagnitude.remaining)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityHint(description)
                    }
                }
                Section("Resets") {
                    let countdownTitle = String(localized: "Time until a reset")
                    let countdownDescription = String(localized: "Shows a short countdown, like 2 h, or a detailed one, like 2 h 28 min.")
                    SettingsRow(title: countdownTitle, description: countdownDescription) {
                        Picker(countdownTitle, selection: $countdownStyle) {
                            Text(Format.current.name(of: CountdownStyle.simple)).tag(CountdownStyle.simple)
                            Text(Format.current.name(of: CountdownStyle.detailed)).tag(CountdownStyle.detailed)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityHint(countdownDescription)
                    }
                    let bankedTitle = String(localized: "Resets available")
                    let bankedDescription = String(localized: "Shows how many resets the account has available, next to the provider's name.")
                    SettingsRow(title: bankedTitle, description: bankedDescription) {
                        Toggle(bankedTitle, isOn: $showBankedResets)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .accessibilityHint(bankedDescription)
                            // As in `ProviderRow`: a switch with a hidden label
                            // exposes no press action.
                            .accessibilityAction { showBankedResets.toggle() }
                    }
                }
                Section("Updates") {
                    let title = String(localized: "Check for updates")
                    let description = String(localized: "Asks GitHub once a day for a newer version of \(Format.appName), without sending any data about you. You install it yourself.")
                    SettingsRow(title: title, description: description) {
                        Toggle(title, isOn: $checkForUpdates)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .accessibilityHint(description)
                            // As in `ProviderRow`: a switch with a hidden label
                            // exposes no press action.
                            .accessibilityAction { checkForUpdates.toggle() }
                    }
                }
            }
            // Under the form, not in a section footer. A grouped row paints
            // a card, and the window sizes to this stack.
            if let versionLine {
                Text(versionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The footer text starts 30pt from the window edge.
                    // This line sits outside the form, so it pads to match.
                    .padding(.horizontal, 30)
                    .padding(.bottom, 16)
            }
        }
    }

    /// The rows follow the panel's card order. Only here can it change, with
    /// buttons that keyboard and VoiceOver can reach. The section has no
    /// header: the selected tab already says "Providers".
    private var providers: some View {
        tabForm {
            Section {
                ForEach(order, id: \.self) { provider in
                    ProviderRow(
                        provider: provider,
                        isOn: isEnabled(provider),
                        moveUp: move(provider, by: -1),
                        moveDown: move(provider, by: 1)
                    )
                    if provider == .cursor, showCursor, core.isCursorAccessGranted {
                        let title = String(localized: "Keychain access")
                        let description = String(localized: "\(Format.appName) can read the key Cursor encrypts its session with.")
                        SettingsRow(title: title, description: description) {
                            Button("Revoke…") { isConfirmingRevocation = true }
                                .accessibilityHint(description)
                        }
                    }
                }
            } footer: {
                Text("The cards follow the order of this list. A provider that's turned off has no card, and \(Format.appName) doesn't read its session or check its usage limits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Background refresh, then the alerts it can fire. Every row but the
    /// first waits for background refresh.
    private var notifications: some View {
        tabForm {
            Section {
                let refreshTitle = String(localized: "Background refresh")
                let refreshDescription = String(localized: "Checks turned-on providers even while the panel is closed.")
                SettingsRow(title: refreshTitle, description: refreshDescription) {
                    Toggle(refreshTitle, isOn: $backgroundRefresh)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityHint(refreshDescription)
                        // As in `ProviderRow`: a switch with a hidden label
                        // exposes no press action.
                        .accessibilityAction { backgroundRefresh.toggle() }
                }
                let intervalTitle = String(localized: "Refresh interval")
                let intervalDescription = String(localized: "How often to check usage limits while the panel is closed.")
                SettingsRow(title: intervalTitle, description: intervalDescription) {
                    Picker(intervalTitle, selection: $intervalMinutes) {
                        ForEach(BackgroundRefresh.intervals, id: \.self) { interval in
                            Text(Format.current.duration(seconds: Int(interval))).tag(Int(interval / 60))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityHint(intervalDescription)
                }
                .disabled(!backgroundRefresh)
            } header: {
                Text("Background refresh")
            } footer: {
                Text("In the background, \(Format.appName) reuses the session it last read when you opened the panel and never asks for keychain access. If a provider's session expires, its checks pause until you open the panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Alerts") {
                alertRow(
                    title: String(localized: "Near a usage limit"),
                    description: String(localized: "Notifies once per window when a usage limit crosses the threshold."),
                    isOn: $alertNearLimit
                )
                let thresholdTitle = String(localized: "Alert threshold")
                let thresholdDescription = String(localized: "Applies to all turned-on providers.")
                SettingsRow(title: thresholdTitle, description: thresholdDescription) {
                    Picker(thresholdTitle, selection: $alertThreshold) {
                        ForEach(AlertSettings.thresholds, id: \.self) { threshold in
                            Text(Format.current.threshold(threshold, in: selectedMagnitude)).tag(Int(threshold))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityHint(thresholdDescription)
                }
                .disabled(!backgroundRefresh || !alertNearLimit)
                alertRow(
                    title: String(localized: "When a limit is reached"),
                    description: String(localized: "Notifies when a usage limit reaches 100% used (0% left)."),
                    isOn: $alertLimitReached
                )
                alertRow(
                    title: String(localized: "When a limit resets"),
                    description: String(localized: "Notifies when a limit at 100% resets and can be used again."),
                    isOn: $alertLimitReset
                )
                if backgroundRefresh, alertNearLimit || alertLimitReached || alertLimitReset, notifier.isDenied {
                    let deniedTitle = String(localized: "Notifications turned off")
                    let deniedDescription = String(localized: "Notifications are turned off for \(Format.appName) in macOS.")
                    SettingsRow(title: deniedTitle, description: deniedDescription) {
                        Button("Open Settings…") { openURL(Notifier.systemSettings) }
                            .accessibilityHint(deniedDescription)
                    }
                }
            }
        }
    }

    /// An alert's switch, which waits for background refresh.
    private func alertRow(title: String, description: String, isOn: Binding<Bool>) -> some View {
        SettingsRow(title: title, description: description) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityHint(description)
                // As in `ProviderRow`: a switch with a hidden label exposes
                // no press action.
                .accessibilityAction { isOn.wrappedValue.toggle() }
        }
        .disabled(!backgroundRefresh)
    }

    /// "Version 0.1.1 (3)" from the bundle, or nothing when either value is
    /// missing. The build writes those keys from `MARKETING_VERSION` and
    /// `CURRENT_PROJECT_VERSION`.
    private var versionLine: String? {
        Format.current.appVersion(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    private func isEnabled(_ provider: Provider) -> Binding<Bool> {
        switch provider {
        case .claude: $showClaude
        case .codex: $showCodex
        case .cursor: $showCursor
        case .antigravity: $showAntigravity
        }
    }

    /// `nil` when `provider` is already at that end of the list.
    private func move(_ provider: Provider, by offset: Int) -> (() -> Void)? {
        guard let index = order.firstIndex(of: provider), order.indices.contains(index + offset) else { return nil }
        return {
            var order = order
            order.swapAt(index, index + offset)
            setOrder(order)
        }
    }

    private func setOrder(_ order: [Provider]) {
        withAnimation { self.order = order }
        ProviderPreferences.save(order, in: .standard)
        setProviderOrder(order)
    }
}

/// The height a tab lays out at, which the window takes.
nonisolated private struct TabHeight: Equatable, Sendable {
    let tab: SettingsTab
    let height: CGFloat
}

/// One switch per provider, described by the session it reads, after the
/// buttons that move it in the card order.
private struct ProviderRow: View {
    let provider: Provider
    @Binding var isOn: Bool
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?

    var body: some View {
        let description = String(localized: "Uses the \(provider.officialApp) session on this Mac.")
        SettingsRow(title: provider.name, logo: provider, description: description) {
            MoveButton(label: String(localized: "Move \(provider.name) Up"), systemImage: "chevron.up", action: moveUp)
            MoveButton(label: String(localized: "Move \(provider.name) Down"), systemImage: "chevron.down", action: moveDown)
            Toggle("Turn On \(provider.name)", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityHint(description)
                // A switch with a hidden label exposes no press action, so
                // VoiceOver could not flip it without this one.
                .accessibilityAction { isOn.toggle() }
        }
    }
}

/// Moves a provider one place in the card order, disabled at the end of the
/// list it would move past.
private struct MoveButton: View {
    let label: String
    let systemImage: String
    let action: (() -> Void)?

    var body: some View {
        Button(label, systemImage: systemImage) { action?() }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(action == nil)
            .help(label)
    }
}

/// A row's title over its secondary description, with its control
/// centered on the trailing side. Laid out by hand because a form row
/// aligns the control with the title's baseline, which lifts a taller
/// control such as a segmented one above the title.
private struct SettingsRow<Control: View>: View {
    let title: String
    /// The provider whose logo leads the title, on a provider's row.
    var logo: Provider?
    let description: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let logo {
                        ProviderLogo(provider: logo)
                    }
                    Text(title)
                }
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            control
        }
    }
}
