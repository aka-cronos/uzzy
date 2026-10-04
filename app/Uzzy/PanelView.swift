import SwiftUI
import UzzyCore

enum PanelLayout {
    /// Shared by the panel and the debug scenario bar, so the bar cannot
    /// widen the popover past the cards.
    static let width: CGFloat = 360
    /// Room below the screen's visible frame for the popover's arrow and a
    /// gap above the Dock or the bottom edge.
    static let screenMargin: CGFloat = 40
}

/// How tall the panel may grow: the visible frame of the screen its icon is
/// on, less a margin. The app updates it before each opening and when the
/// screens change.
@Observable
final class PanelBounds {
    var maxHeight: CGFloat = .infinity
}

struct PanelView: View {
    let core: UsageCore
    let updates: UpdateChecker
    let bounds: PanelBounds
    /// Taken by views above the panel in the same popover.
    var heightAbove: CGFloat = 0
    let openSettings: () -> Void
    /// Opens the download of the latest version in the browser.
    let downloadUpdate: () -> Void
    @AppStorage("displayMagnitude") private var selectedMagnitude: QuotaMagnitude = .used
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var cardsHeight: CGFloat = 0

    /// The cards keep their own height until the panel would outgrow the
    /// screen; past that they scroll, and the header and footer stay put.
    private var cardsViewportHeight: CGFloat {
        let available = bounds.maxHeight - heightAbove - headerHeight - footerHeight
        return max(0, min(cardsHeight, available))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(Format.appName).font(.headline)
                if let version = updates.availableVersion {
                    UpdateButton(version: version, action: downloadUpdate)
                }
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 10)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }

            if core.state.cards.isEmpty {
                VStack(spacing: 10) {
                    Text("No active providers").font(.headline)
                    Text("Turn on a provider in Settings to see its usage limits.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Open Settings", action: openSettings)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 32)
            } else {
                ScrollView {
                    // Recomputes the time left until each reset every minute.
                    TimelineView(.everyMinute) { _ in
                        VStack(spacing: 0) {
                            ForEach(core.state.cards, id: \.provider) { card in
                                CardView(card: card, magnitude: core.state.magnitude, now: core.now())
                                if card.provider != core.state.cards.last?.provider {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { cardsHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: cardsViewportHeight)
            }

            VStack(spacing: 0) {
                Divider()
                HStack {
                    // Quotas live only in memory, so quitting has nothing to save.
                    Button("Quit") { NSApp.terminate(nil) }
                        .accessibilityLabel(Format.current.quitApp)
                        .accessibilityInputLabels([String(localized: "Quit"), Format.current.quitApp])
                        .help(Format.current.quitApp + " (⌘Q)")
                    Spacer()
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                            .frame(width: 18, height: 18)
                    }
                    .accessibilityLabel(Format.current.settings)
                    .help("Open Settings (⌘,)")
                    if !core.state.cards.isEmpty {
                        Button(action: core.refresh) {
                            Group {
                                if core.state.isQuerying {
                                    ProgressView()
                                        .controlSize(.small)
                                        .accessibilityHidden(true)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            .frame(width: 18, height: 18)
                        }
                        .accessibilityLabel("Refresh")
                        .accessibilityValue(core.state.isQuerying ? Text("Query in progress") : Text(verbatim: ""))
                        .help("Check usage limits now")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { footerHeight = $0 }
        }
        .frame(width: PanelLayout.width)
        // The popover draws the system's Liquid Glass behind this view. An
        // opaque fill would cover it, so it would ignore the Appearance setting.
        .containerBackground(.clear, for: .window)
        .onAppear { core.show(selectedMagnitude) }
        .onChange(of: selectedMagnitude) { _, magnitude in core.show(magnitude) }
    }
}

/// Next to the app's name while a newer version is published: a pill that
/// opens its download. Installing it stays by hand.
private struct UpdateButton: View {
    let version: String
    let action: () -> Void

    var body: some View {
        Button("Update", action: action)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .accessibilityLabel(Format.current.downloadUpdate(version))
            .accessibilityInputLabels([String(localized: "Update"), Format.current.downloadUpdate(version)])
            .help(Format.current.downloadUpdate(version))
    }
}

private struct CardView: View {
    let card: Card
    let magnitude: QuotaMagnitude
    let now: Date
    @AppStorage("showBankedResets") private var showBankedResets = true

    private var lastReadAt: Date? {
        let quotas: [Quota]
        switch card.content {
        case .quotas(let values), .stale(let values, _): quotas = values
        default: return nil
        }
        // A missing or uninterpretable figure has no valid reading to date.
        return quotas.compactMap { quota -> Date? in
            switch quota.value {
            case .percent, .spend: quota.readAt
            case .uninterpretable, .unavailable: nil
            }
        }.min()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                CardTitle(provider: card.provider, plan: card.plan)
                if showBankedResets, let bankedResets = card.bankedResets {
                    BankedResetsButton(count: bankedResets)
                }
                Spacer()
                if let lastReadAt {
                    Text("Last reading: \(Format.current.timeAgo(lastReadAt, now: now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        // The exact moment, which the relative time leaves out.
                        .help(Format.current.dayAndTime(lastReadAt, now: now))
                }
            }

            switch card.content {
            case .loading:
                Message(title: "Checking usage limits…", detail: "No valid data yet.")
            case .loadingNewAccount:
                Message(
                    title: "Checking new account…",
                    detail: "The \(card.provider.officialApp) session belongs to another account. The previous account's figures were cleared."
                )
            case .failed(let failure):
                FailureMessage(failure: failure, provider: card.provider, now: now)
            case .quotas(let quotas):
                QuotasView(quotas: quotas, magnitude: magnitude, now: now)
            case .stale(let quotas, let failure):
                // Why the figures below could not be refreshed.
                FailureMessage(failure: failure, provider: card.provider, now: now)
                QuotasView(quotas: quotas, magnitude: magnitude, now: now)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The provider's name and, when the provider reports it, the account's plan:
/// «Claude · Max». A plan that does not fit is cut before the name is.
private struct CardTitle: View {
    let provider: Provider
    let plan: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(provider.name)
                .fontWeight(.semibold)
                .layoutPriority(1)
            if let plan {
                Text(verbatim: "· \(plan)")
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Format.current.cardTitle(provider.name, plan: plan))
    }
}

/// The account's banked resets, next to the provider's name: a pill with the
/// count that opens a popover spelling it out. It is not a quota: no bar, no
/// percentage and no reset date.
private struct BankedResetsButton: View {
    let count: Int
    @State private var isShowingDetail = false

    /// A gauge with a backward arrow: a limit set back.
    static let symbol = "gauge.open.righthalf.dotted.with.needle.and.arrow.trianglehead.backward"

    var body: some View {
        Button { isShowingDetail.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: Self.symbol)
                    .font(.caption2)
                Text(count, format: .number)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.fill.secondary, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Format.current.bankedResets(count))
        .help(Format.current.bankedResets(count))
        .popover(isPresented: $isShowingDetail, arrowEdge: .bottom) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: Self.symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Format.current.bankedResets(count)).font(.headline)
                    Text(Format.current.bankedResetsNote(count))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .fixedSize()
        }
    }
}

private struct QuotasView: View {
    let quotas: [Quota]
    let magnitude: QuotaMagnitude
    let now: Date

    var body: some View {
        ForEach(quotas, id: \.period) { quota in
            QuotaView(quota: quota, magnitude: magnitude, now: now)
        }
    }
}

private struct QuotaView: View {
    let quota: Quota
    let magnitude: QuotaMagnitude
    let now: Date
    @AppStorage(CountdownStyle.key) private var countdownStyle: CountdownStyle = .simple

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch quota.value {
            // Every remaining figure is calculated as 100 − used, so the card
            // does not mark it: the chosen magnitude already says so.
            case .percent(let percent, _):
                // The label and the bar come from the same value, so they
                // always show the same magnitude.
                HStack(alignment: .firstTextBaseline) {
                    QuotaName(quota: quota)
                    Spacer()
                    Text(Format.current.percent(percent))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(quota.isStale ? .secondary : .primary)
                    Text(Format.current.name(of: magnitude)).font(.caption).foregroundStyle(.secondary)
                }
                Bar(fraction: percent / 100)
                    .opacity(quota.isStale ? 0.5 : 1)
                if let reset = quota.reset {
                    Text(Format.current.reset(reset, now: now, countdown: countdownStyle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            // Money, not a quota figure: no magnitude, no bar and no reset.
            case .spend(let spent, let limit):
                HStack(alignment: .firstTextBaseline) {
                    QuotaName(quota: quota)
                    Spacer()
                    Text(Format.current.usageCredits(spent, limit: limit))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(quota.isStale ? .secondary : .primary)
                }
            // No valid reading of this quota, so no reset or reading time to vouch for.
            case .uninterpretable:
                QuotaNotice(period: quota.period, notice: "Unreadable data")
            case .unavailable:
                QuotaNotice(period: quota.period, notice: "Usage limit unavailable")
            }
        }
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
    }
}

/// A quota's name, marked when its figure is stale.
private struct QuotaName: View {
    let quota: Quota

    var body: some View {
        Text(Format.current.name(of: quota.period))
        if quota.isStale {
            Text("Out of date").font(.caption.weight(.semibold)).foregroundStyle(.orange)
        }
    }
}

/// A quota without a percentage to show: no figure and no bar.
private struct QuotaNotice: View {
    let period: QuotaPeriod
    let notice: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Format.current.name(of: period))
            Spacer()
            Text(notice).fontWeight(.semibold).foregroundStyle(.orange)
        }
    }
}

private struct Bar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.tint).frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

private struct Message: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fontWeight(.semibold)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }
}

/// Why the card has no quotas, and what to do about it.
private struct FailureMessage: View {
    let failure: Failure
    let provider: Provider
    let now: Date

    var body: some View {
        switch failure {
        case .noSession:
            Message(title: "Not signed in", detail: "Sign in to \(provider.officialApp) and click Refresh.")
        case .sessionWithoutSubscriptionQuotas:
            Message(
                title: "This session has no subscription usage limits",
                detail: "The \(provider.officialApp) session isn't from a subscription (e.g., it uses an API key). Sign in to \(provider.officialApp) with your subscription and click Refresh."
            )
        case .sessionAccessDenied:
            Message(
                title: "No access to the session",
                detail: "Access to the \(provider.officialApp) session in the keychain was denied. Click Refresh to ask again."
            )
        case .sessionStoreUnavailable:
            if provider == .claude {
                Message(
                    title: "Keychain unavailable",
                    detail: "Couldn't read the Claude Code session in the keychain. Check that it's unlocked and click Refresh."
                )
            } else {
                Message(
                    title: "Couldn't read the session",
                    detail: "Couldn't open the \(provider.officialApp) session. Check that the official app works and click Refresh."
                )
            }
        case .sessionStoreBusy:
            Message(
                title: "Session busy",
                detail: "The \(provider.officialApp) database is busy. Wait a moment and click Refresh."
            )
        case .incompatibleSession:
            Message(
                title: "Incompatible session",
                detail: "The \(provider.officialApp) session is in a format \(Format.appName) doesn't recognize."
            )
        case .sessionExpired:
            Message(title: "Session expired", detail: "Renew the session in \(provider.officialApp) and click Refresh.")
        case .accessRefused:
            Message(
                title: "Access refused",
                detail: "\(provider.name) refused the query. It may be an account restriction; check it in \(provider.officialApp) and click Refresh."
            )
        case .reusedSessionRejected:
            Message(
                title: "Unconfirmed",
                detail: "\(provider.name) didn't accept the saved session. Click Refresh to check it again."
            )
        case .offline:
            Message(title: "Offline", detail: "Couldn't connect to \(provider.name). Click Refresh to try again.")
        case .timedOut:
            Message(title: "Timed out", detail: "\(provider.name) didn't respond in time. Click Refresh to try again.")
        case .serverError(let status):
            Message(title: "Server error", detail: "\(provider.name) responded with an error (\(status)). Click Refresh to try again.")
        case .rateLimited(let until):
            if let until {
                Message(
                    title: "Too many queries",
                    detail: "\(provider.name) asked to wait. It will be checked again from \(Format.current.dayAndTime(until, now: now))."
                )
            } else {
                Message(title: "Too many queries", detail: "\(provider.name) asked to wait. It will be checked again shortly.")
            }
        case .incompatibleResponse, .responseTooLarge:
            Message(
                title: "Incompatible response",
                detail: "\(provider.name) responded in a format \(Format.appName) doesn't recognize. Its service may have changed."
            )
        case .incompatibleResetFormat:
            Message(
                title: "Incompatible Cursor reset",
                detail: "Cursor sent the reset date in a format \(Format.appName) doesn't recognize. Click Refresh; if it continues, the integration needs an update."
            )
        }
    }
}

extension Provider {
    var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    /// The app whose session the card reuses.
    var officialApp: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .cursor: "Cursor"
        }
    }
}
