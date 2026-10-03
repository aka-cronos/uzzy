import SwiftUI
import UzzyCore

/// A native grouped settings pane: each row has a title, a short description
/// and a trailing control, as in System Settings.
struct SettingsView: View {
    static let width: CGFloat = 480

    let setProviderEnabled: @MainActor (Provider, Bool) -> Void
    let setProviderOrder: @MainActor ([Provider]) -> Void
    @AppStorage("displayMagnitude") private var selectedMagnitude: QuotaMagnitude = .used
    @AppStorage(CountdownStyle.key) private var countdownStyle: CountdownStyle = .simple
    @AppStorage(ProviderPreferences.claudeKey) private var showClaude = true
    @AppStorage(ProviderPreferences.codexKey) private var showCodex = true
    @AppStorage(ProviderPreferences.cursorKey) private var showCursor = true
    /// `@AppStorage` cannot hold a list, so the order is saved by hand.
    @State private var order = ProviderPreferences.order(in: .standard)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            form
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
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: showClaude) { _, enabled in setProviderEnabled(.claude, enabled) }
        .onChange(of: showCodex) { _, enabled in setProviderEnabled(.codex, enabled) }
        .onChange(of: showCursor) { _, enabled in setProviderEnabled(.cursor, enabled) }
    }

    private var form: some View {
        Form {
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
            }
            // The rows follow the panel's card order. Only here can it change,
            // with buttons that keyboard and VoiceOver can reach.
            Section {
                ForEach(order, id: \.self) { provider in
                    ProviderRow(
                        provider: provider,
                        isOn: isEnabled(provider),
                        moveUp: move(provider, by: -1),
                        moveDown: move(provider, by: 1)
                    )
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("The cards follow the order of this list. A provider that's turned off has no card, and \(Format.appName) doesn't read its session or check its usage limits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
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

/// One switch per provider, described by the session it reads, after the
/// buttons that move it in the card order.
private struct ProviderRow: View {
    let provider: Provider
    @Binding var isOn: Bool
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?

    var body: some View {
        let description = String(localized: "Uses the \(provider.officialApp) session on this Mac.")
        SettingsRow(title: provider.name, description: description) {
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
    let description: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            control
        }
    }
}
