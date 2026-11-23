import Foundation
import Observation

/// Refresh coordinator and in-memory panel state.
/// It is the only test seam: its external dependencies are injected.
@MainActor
@Observable
public final class UsageCore {
    /// Depends on the clock too: a reset that passes changes the state.
    public var state: PanelState {
        let now = clock.now()
        return PanelState(
            magnitude: magnitude,
            cards: orderedProviders.filter(\.isEnabled).map {
                var card = Card(
                    provider: $0.provider,
                    content: $0.content(in: magnitude, at: now),
                    bankedResets: $0.bankedResets,
                    plan: $0.plan
                )
                card.creditBalance = $0.creditBalanceState.visible(at: now)
                card.cloudCredit = $0.cloudCreditState.visible(at: now)
                return card
            },
            isQuerying: providers.contains { $0.isEnabled && $0.isQuerying }
        )
    }

    public var enabledProviders: Set<Provider> {
        Set(providers.filter(\.isEnabled).map(\.provider))
    }

    /// Every provider in the panel's card order, disabled ones included so
    /// they keep their place.
    public private(set) var order: [Provider]

    /// How often providers are queried while the panel is open. Opening the
    /// panel does not query a provider whose reading is younger than this.
    nonisolated static let refreshInterval: TimeInterval = 5 * 60

    private var magnitude: QuotaMagnitude
    /// One per provider. Each is queried on its own.
    private let providers: [ProviderRefresh]
    /// The only scheduled query. `nil` while the panel is closed and
    /// background refresh is off; replacing it cancels the one before.
    @ObservationIgnored private var cadence: ScheduledWork? {
        didSet { oldValue?.cancel() }
    }

    /// Whether providers are also queried while the panel is closed.
    public private(set) var backgroundRefresh: BackgroundRefresh
    public private(set) var alerts: AlertSettings
    /// Receives each alert that fires. Alerts only fire while background
    /// refresh is on and the panel is closed.
    @ObservationIgnored public var alertFired: (@MainActor (UsageAlert) -> Void)?
    /// How long after a limited quota's reset its verification query waits,
    /// so a clock slightly ahead of the provider's does not query too early.
    public nonisolated static let resetVerificationDelay: TimeInterval = 5
    @ObservationIgnored private var isPanelOpen = false
    @ObservationIgnored private var tracker: AlertTracker
    /// At most one per provider: the query that verifies its earliest
    /// limited quota reset. Replacing one cancels it.
    @ObservationIgnored private var resetVerifications: [Provider: ScheduledWork] = [:]

    private let clock: any WallClock
    private let cursorAccess: any AccessConsent

    /// The user let the app read the key Cursor encrypts its session with.
    public private(set) var isCursorAccessGranted: Bool

    public init(
        claudeSessionReader: any SessionReader,
        codexSessionReader: any SessionReader,
        cursorSessionReader: any SessionReader,
        antigravitySessionReader: any SessionReader,
        cursorAccess: any AccessConsent = MemoryAccessConsent(),
        transport: any HTTPTransport,
        clock: any WallClock,
        log: any EventLog = SystemLog(),
        initialMagnitude: QuotaMagnitude = .used,
        initialEnabledProviders: Set<Provider> = Set(Provider.allCases),
        initialOrder: [Provider] = Provider.allCases,
        initialBackgroundRefresh: BackgroundRefresh = .off,
        initialAlerts: AlertSettings = .off
    ) {
        self.clock = clock
        backgroundRefresh = initialBackgroundRefresh
        alerts = initialAlerts
        tracker = AlertTracker(threshold: initialAlerts.threshold)
        self.cursorAccess = cursorAccess
        magnitude = initialMagnitude
        order = Provider.order(completing: initialOrder)
        providers = [
            ProviderRefresh(Claude.self, sessionReader: claudeSessionReader, transport: transport, clock: clock, log: log,
                            isEnabled: initialEnabledProviders.contains(.claude)),
            ProviderRefresh(Codex.self, sessionReader: codexSessionReader, transport: transport, clock: clock, log: log,
                            isEnabled: initialEnabledProviders.contains(.codex)),
            ProviderRefresh(Cursor.self, sessionReader: cursorSessionReader, transport: transport, clock: clock, log: log,
                            isEnabled: initialEnabledProviders.contains(.cursor)),
            ProviderRefresh(Antigravity.self, sessionReader: antigravitySessionReader, transport: transport, clock: clock, log: log,
                            isEnabled: initialEnabledProviders.contains(.antigravity)),
        ]
        // A provider turned off while the app was not running keeps no consent.
        if !initialEnabledProviders.contains(.cursor) {
            cursorAccess.setGranted(false)
        }
        isCursorAccessGranted = cursorAccess.isGranted()
        for refresh in providers {
            refresh.readingChanged = { [weak self] provider in self?.readingChanged(of: provider) }
        }
    }

    public func now() -> Date {
        clock.now()
    }

    /// Expresses every quota as used or remaining quota.
    public func show(_ magnitude: QuotaMagnitude) {
        self.magnitude = magnitude
    }

    /// A disabled provider has neither a card nor session or network work,
    /// and keeps nothing of its session. Turning Cursor off also withdraws
    /// the consent to read its key, so turning it on asks again.
    public func setEnabled(_ enabled: Bool, for provider: Provider) {
        if !enabled, provider == .cursor {
            setCursorAccess(false)
        }
        if !enabled {
            tracker.forget(provider)
            setResetVerification(nil, for: provider)
        }
        refresh(of: provider)?.setEnabled(enabled)
    }

    /// Turning it on is a user action: providers with no session in memory
    /// read it, which may show the Keychain prompt, so the queries while the
    /// panel is closed have one to reuse. The alerts start from the next
    /// fresh reading, which only sets their baseline.
    public func setBackgroundRefresh(_ isOn: Bool) {
        guard isOn != backgroundRefresh.isOn else { return }
        backgroundRefresh.isOn = isOn
        tracker.forgetAll()
        if isOn {
            providers.forEach { $0.backgroundRefreshTurnedOn() }
            rescheduleResetVerifications()
        } else {
            cancelResetVerifications()
        }
        if !isPanelOpen { scheduleNextQuery() }
    }

    /// Restarts the closed panel's cadence from now. Never under
    /// `BackgroundRefresh.shortestInterval`.
    public func setBackgroundInterval(_ interval: TimeInterval) {
        let previous = backgroundRefresh.interval
        backgroundRefresh.interval = interval
        guard backgroundRefresh.interval != previous, !isPanelOpen else { return }
        scheduleNextQuery()
    }

    /// A new threshold restarts the near-limit alerts against it.
    public func setAlerts(_ alerts: AlertSettings) {
        let resetWasOn = self.alerts.limitReset
        self.alerts = alerts
        tracker.setThreshold(alerts.threshold)
        if alerts.limitReset != resetWasOn { rescheduleResetVerifications() }
    }

    /// The user consents, on the Cursor card, to let the app read the key
    /// Cursor encrypts its session with, and the session is read at once:
    /// a user action, so macOS may show its Keychain prompt.
    public func allowCursorAccess() {
        setCursorAccess(true)
        guard let cursor = refresh(of: .cursor), cursor.isEnabled else { return }
        cursor.restart()
        cursor.refresh()
    }

    /// Withdraws that consent and forgets the decrypted session. macOS may
    /// still trust the app with the key; only the user can remove it from
    /// the item's access control.
    public func revokeCursorAccess() {
        setCursorAccess(false)
        refresh(of: .cursor)?.restart()
    }

    private func setCursorAccess(_ granted: Bool) {
        cursorAccess.setGranted(granted)
        isCursorAccessGranted = granted
    }

    private func refresh(of provider: Provider) -> ProviderRefresh? {
        providers.first { $0.provider == provider }
    }

    /// Only sorts the cards: no provider is read or queried again.
    public func setOrder(_ order: [Provider]) {
        self.order = Provider.order(completing: order)
    }

    /// Reads the sessions again, which may show the Keychain prompt: opening
    /// the panel is a user action.
    public func panelOpened() {
        isPanelOpen = true
        scheduleNextQuery()
        providers.forEach { $0.panelOpened() }
    }

    /// The Actualizar button: reads the sessions and queries even when the
    /// readings are fresh or the sessions were rejected.
    public func refresh() {
        providers.forEach { $0.refresh() }
    }

    /// Queries on waking from sleep while the panel is open, or background
    /// refresh is on, and restarts the cadence and the reset verifications
    /// from then.
    public func systemWoke() {
        guard isPanelOpen || backgroundRefresh.isOn else { return }
        providers.forEach { $0.queryOnItsOwn() }
        scheduleNextQuery()
        rescheduleResetVerifications()
    }

    /// Stops scheduling queries, unless background refresh is on: then they
    /// go on at its interval. A query in flight still finishes.
    public func panelClosed() {
        isPanelOpen = false
        scheduleNextQuery()
        providers.forEach { $0.panelClosed() }
    }

    /// Returns once no query of `provider`, or of any provider, is in flight.
    public func queriesFinished(of provider: Provider? = nil) async {
        for refresh in providers where provider == nil || refresh.provider == provider {
            await refresh.queryFinished()
        }
    }

    private var orderedProviders: [ProviderRefresh] {
        order.compactMap { provider in providers.first { $0.provider == provider } }
    }

    /// The open panel's cadence, background refresh's while it is closed, or
    /// none. Replaces any query scheduled before.
    private func scheduleNextQuery() {
        let interval: TimeInterval
        if isPanelOpen {
            interval = Self.refreshInterval
        } else if backgroundRefresh.isOn {
            interval = backgroundRefresh.interval
        } else {
            cadence = nil
            return
        }
        cadence = clock.schedule(at: clock.now().addingTimeInterval(interval)) { [weak self] in
            guard let self else { return }
            providers.forEach { $0.queryOnItsOwn() }
            scheduleNextQuery()
        }
    }

    /// While background refresh is on, every fresh reading moves the alerts
    /// on, even with the panel open, so what the person saw there never
    /// fires later. Only a closed panel lets them through.
    private func readingChanged(of provider: Provider) {
        guard backgroundRefresh.isOn, let providerRefresh = refresh(of: provider), providerRefresh.isEnabled,
              let fresh = providerRefresh.alertReading(at: clock.now())
        else { return }
        let fired = tracker.observe(provider, accountID: fresh.accountID, quotas: fresh.quotas)
        scheduleResetVerification(for: provider, quotas: fresh.quotas)
        guard !isPanelOpen else { return }
        for alert in fired where alerts.allows(alert) {
            alertFired?(alert)
        }
    }

    /// A limited quota with a known reset is queried once right after it,
    /// instead of at the next tick, so its reset is confirmed promptly. A
    /// reset another limit at 100% outlasts confirms nothing worth telling,
    /// so it is not queried early. Only while background refresh and reset
    /// alerts are on.
    private func scheduleResetVerification(for provider: Provider, quotas: [AlertQuota]) {
        guard backgroundRefresh.isOn, alerts.limitReset,
              let resetAt = AlertQuota.earliestUsableReset(of: quotas)
        else {
            setResetVerification(nil, for: provider)
            return
        }
        let work = clock.schedule(at: resetAt.addingTimeInterval(Self.resetVerificationDelay)) { [weak self] in
            guard let self else { return }
            resetVerifications[provider] = nil
            refresh(of: provider)?.queryOnItsOwn()
        }
        setResetVerification(work, for: provider)
    }

    private func setResetVerification(_ work: ScheduledWork?, for provider: Provider) {
        resetVerifications[provider]?.cancel()
        resetVerifications[provider] = work
    }

    /// From each provider's fresh reading, e.g. on waking from sleep.
    private func rescheduleResetVerifications() {
        let now = clock.now()
        for refresh in providers {
            let quotas = refresh.isEnabled ? refresh.alertReading(at: now)?.quotas ?? [] : []
            scheduleResetVerification(for: refresh.provider, quotas: quotas)
        }
    }

    private func cancelResetVerifications() {
        resetVerifications.values.forEach { $0.cancel() }
        resetVerifications = [:]
    }
}
