import Foundation

// Debug scenarios: never in a Release build.
#if DEBUG

/// A state of the panel to review by eye in a Debug build, without touching
/// the accounts. It drives a usage core through the same seam as the tests:
/// fake sessions, a fake transport answering with the sample responses, and
/// a clock that only moves when the scenario moves it. All data is fictional.
public struct Scenario: Sendable, Identifiable, Hashable {
    /// Stable, for choosing a scenario from the command line.
    public let id: String
    /// The state it shows, as the panel names it.
    public let name: String
    private let play: @MainActor @Sendable (Stage) async -> Void

    init(_ id: String, _ name: String, play: @escaping @MainActor @Sendable (Stage) async -> Void) {
        self.id = id
        self.name = name
        self.play = play
    }

    /// A usage core with its panel open, showing the scenario. Closing and
    /// opening the panel again keeps showing it.
    @MainActor
    public func start(
        enabledProviders: Set<Provider> = Set(Provider.allCases),
        order: [Provider] = Provider.allCases
    ) async -> UsageCore {
        let stage = Stage(enabledProviders: enabledProviders, order: order)
        await play(stage)
        return stage.core
    }

    public static func == (lhs: Scenario, rhs: Scenario) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Scenario {
    /// Every scenario, in the order to review them. Together they show every
    /// visible state of the panel.
    public static let all: [Scenario] = [
        quotas, usageCredits, uncappedUsageCredits, loading, newAccount, stale, pendingConfirmation, unknownReset, unavailable, withoutSubscriptionQuotas,
        uninterpretable, noSession, sessionExpired, reusedSessionRejected, sessionAccessDenied, unavailableSessionStores,
        incompatibleSession, incompatibleResponse, incompatibleCursorReset,
        networkFailures, refused, longContent, bankedResets,
    ]

    /// Every card shows the sample quotas, and its plan next to its name:
    /// «Claude · Max», «Codex · Plus» and «Cursor · Pro+».
    public static let quotas = Scenario("quotas", "Cuotas al día") { stage in
        await stage.openPanel()
    }

    /// «Créditos de uso»: after its subscription quotas, Claude reports
    /// 53.06 US dollars of usage credits spent against a 40-dollar monthly
    /// limit. Spending past the limit is shown as it is.
    public static let usageCredits = Scenario("usageCredits", "Créditos de uso") { stage in
        await stage.transport.answer(with: .json(claudeWithUsageCredits(monthlyLimit: "4000")), for: .claude)
        await stage.openPanel()
    }

    /// «Créditos de uso» without a monthly limit: only the spend is shown.
    public static let uncappedUsageCredits = Scenario("uncappedUsageCredits", "Créditos de uso sin límite") { stage in
        await stage.transport.answer(with: .json(claudeWithUsageCredits(monthlyLimit: "null")), for: .claude)
        await stage.openPanel()
    }

    /// Claude's sample windows with 5306 cents of usage credits spent.
    private static func claudeWithUsageCredits(monthlyLimit: String) -> String {
        #"""
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "extra_usage": {"is_enabled": true, "monthly_limit": \#(monthlyLimit), "used_credits": 5306, "utilization": null, "currency": "USD"}
        }
        """#
    }

    /// «Consultando cuotas»: the first query of every card is still running.
    public static let loading = Scenario("loading", "Consultando cuotas") { stage in
        await stage.transport.hold()
        await stage.openPanel(waitingFor: [])
        await stage.transport.waitForRequests(stage.core.enabledProviders.count)
    }

    /// «Consultando nueva cuenta»: every session changed to another account,
    /// whose first query is still running.
    public static let newAccount = Scenario("newAccount", "Consultando nueva cuenta") { stage in
        await stage.openPanel()
        await stage.answerEverySession(with: .session(Session(accessToken: "other-token", accountID: "other-account")))
        await stage.transport.hold()
        stage.core.refresh()
        await stage.transport.waitForRequests(stage.core.enabledProviders.count * 2)
    }

    /// «Desactualizado»: a later query of every card failed, so each keeps
    /// its last valid reading, 20 minutes old.
    public static let stale = Scenario("stale", "Desactualizado") { stage in
        await stage.openPanel()
        stage.core.panelClosed()
        stage.clock.advance(by: 20 * 60)
        await stage.transport.answer(with: .networkError, for: .claude)
        await stage.transport.answer(with: .status(503), for: .codex)
        await stage.transport.answer(with: .timeout, for: .cursor)
        await stage.openPanel()
    }

    /// «Pendiente de confirmar»: Claude's 5-hour reset passed and the query
    /// after it failed, so the figure is stale and the reset unconfirmed.
    public static let pendingConfirmation = Scenario("pendingConfirmation", "Pendiente de confirmar") { stage in
        await stage.openPanel()
        stage.core.panelClosed()
        // 2026-09-23T17:30:00Z, half an hour after Claude's 5-hour reset.
        stage.clock.move(to: Date(timeIntervalSince1970: 1_790_184_600))
        await stage.transport.answer(with: .networkError, for: .claude)
        await stage.openPanel()
    }

    /// «Reinicio desconocido»: Claude sends no date for the weekly reset.
    public static let unknownReset = Scenario("unknownReset", "Reinicio desconocido") { stage in
        await stage.transport.answer(with: .json(#"""
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": null}
        }
        """#), for: .claude)
        await stage.openPanel()
    }

    /// «Cuota no disponible»: Claude leaves out the weekly quota.
    public static let unavailable = Scenario("unavailable", "Cuota no disponible") { stage in
        await stage.transport.answer(with: .json(#"""
        {"five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"}}
        """#), for: .claude)
        await stage.openPanel()
    }

    /// «Esta sesión no ofrece cuotas de suscripción»: Codex CLI is signed in
    /// with an API key, which has no subscription quotas. It stands in for
    /// «Cuotas no disponibles para este plan»: no validated response shows
    /// that a plan has no quotas yet, so the core has no such state.
    public static let withoutSubscriptionQuotas = Scenario(
        "withoutSubscriptionQuotas", "Esta sesión no ofrece cuotas de suscripción"
    ) { stage in
        await stage.sessionReaders[.codex]?.answer(with: .withoutSubscriptionQuotas)
        await stage.openPanel()
    }

    /// «Dato no interpretable»: Claude's 5-hour figure is over 100 and its
    /// weekly copies contradict each other; Cursor's Other Models is negative.
    public static let uninterpretable = Scenario("uninterpretable", "Dato no interpretable") { stage in
        await stage.transport.answer(with: .json(#"""
        {
          "five_hour": {"utilization": 140.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "limits": [{"kind": "weekly_all", "percent": 80.0, "resets_at": "2026-09-25T09:00:00.000000+00:00", "scope": null}]
        }
        """#), for: .claude)
        await stage.transport.answer(with: .json(#"""
        {"billingCycleEnd": "1791590400000", "planUsage": {"autoPercentUsed": 18.5, "apiPercentUsed": -3}}
        """#), for: .cursor)
        await stage.openPanel()
    }

    /// «Sin sesión»: no official app is signed in.
    public static let noSession = Scenario("noSession", "Sin sesión") { stage in
        await stage.answerEverySession(with: .noSession)
        await stage.openPanel()
    }

    /// «Sesión vencida»: every provider rejects its session (401).
    public static let sessionExpired = Scenario("sessionExpired", "Sesión vencida") { stage in
        await stage.transport.answer(with: .status(401))
        await stage.openPanel()
    }

    /// «Sin confirmar»: five minutes after a successful reading, every
    /// provider rejects the session the automatic query reused (401), so the
    /// figures go stale. The check made on opening the panel again is held,
    /// so reopening keeps showing the state.
    public static let reusedSessionRejected = Scenario("reusedSessionRejected", "Sin confirmar") { stage in
        await stage.openPanel()
        await stage.transport.answer(with: .status(401))
        stage.clock.advance(by: UsageCore.refreshInterval)
        await stage.core.queriesFinished()
        stage.core.panelClosed()
        await stage.transport.hold()
        stage.core.panelOpened()
        await stage.transport.waitForRequests(stage.core.enabledProviders.count * 3)
    }

    /// «Sin acceso a la sesión»: the user denied the Keychain prompt for
    /// Claude Code's session.
    public static let sessionAccessDenied = Scenario("sessionAccessDenied", "Sin acceso a la sesión") { stage in
        await stage.sessionReaders[.claude]?.answer(with: .accessDenied)
        await stage.openPanel()
    }

    /// The Keychain cannot be read, and Cursor's session database is busy.
    public static let unavailableSessionStores = Scenario("unavailableSessionStores", "Sesiones no disponibles") { stage in
        await stage.sessionReaders[.claude]?.answer(with: .storeUnavailable)
        await stage.sessionReaders[.cursor]?.answer(with: .storeBusy)
        await stage.openPanel()
    }

    /// «Sesión incompatible»: every session is stored in an unknown format.
    public static let incompatibleSession = Scenario("incompatibleSession", "Sesión incompatible") { stage in
        await stage.answerEverySession(with: .unknownFormat)
        await stage.openPanel()
    }

    /// «Respuesta incompatible»: every provider answers in a format the app
    /// does not understand.
    public static let incompatibleResponse = Scenario("incompatibleResponse", "Respuesta incompatible") { stage in
        await stage.transport.answer(with: .json("<html>Sample maintenance page</html>"), for: .claude)
        await stage.transport.answer(with: .codex(rateLimit: "null"), for: .codex)
        await stage.transport.answer(with: .json("{}"), for: .cursor)
        await stage.openPanel()
    }

    /// Cursor sends its billing-cycle end as a number instead of a string.
    public static let incompatibleCursorReset = Scenario("incompatibleCursorReset", "Reinicio de Cursor incompatible") { stage in
        await stage.transport.answer(with: .json("""
            {"billingCycleEnd": 1791590400000, "planUsage": {"autoPercentUsed": 18.5, "apiPercentUsed": 42.75}}
            """), for: .cursor)
        await stage.openPanel()
    }

    /// Network and server failures with no previous reading: no connection,
    /// no answer in time and a server error.
    public static let networkFailures = Scenario("networkFailures", "Fallos de red o del servidor") { stage in
        await stage.transport.answer(with: .networkError, for: .claude)
        await stage.transport.answer(with: .timeout, for: .codex)
        await stage.transport.answer(with: .status(503), for: .cursor)
        await stage.openPanel()
    }

    /// Claude refuses the query (403); Codex asks to wait 10 minutes and
    /// Cursor asks to wait without saying how long (429).
    public static let refused = Scenario("refused", "Acceso rechazado y demasiadas consultas") { stage in
        await stage.transport.answer(with: .status(403), for: .claude)
        await stage.transport.answer(
            with: .response(HTTPResponse(status: 429, headers: ["Retry-After": "600"], body: Data())), for: .codex
        )
        await stage.transport.answer(with: .status(429), for: .cursor)
        await stage.openPanel()
    }
}

extension Scenario {
    /// Names long enough to wrap, one of them without spaces to break at.
    public static let longLimitNames = [
        "Sample Model with a Deliberately Long Display Name",
        "Another-Sample-Model-Name-Without-Any-Spaces",
    ]

    /// A panel taller than a short screen: Claude and Codex add per-model
    /// limits, some with long names, and Cursor's figures went stale after a
    /// timeout, so its card also explains the failure.
    public static let longContent = Scenario("longContent", "Contenido largo") { stage in
        await stage.transport.answer(with: .json(#"""
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "seven_day_sonnet": {"utilization": 12.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "seven_day_opus": {"utilization": 48.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "limits": [
            {"kind": "weekly_scoped", "percent": 20.0, "resets_at": "2026-09-25T09:00:00.000000+00:00",
             "scope": {"model": {"display_name": "\#(longLimitNames[0])"}}},
            {"kind": "weekly_scoped", "percent": 7.5, "resets_at": "2026-09-25T09:00:00.000000+00:00",
             "scope": {"model": {"display_name": "\#(longLimitNames[1])"}}}
          ]
        }
        """#), for: .claude)
        let windows = #"""
        {
          "primary_window": {"used_percent": 3, "limit_window_seconds": 18000, "reset_at": 1790186400},
          "secondary_window": {"used_percent": 9, "limit_window_seconds": 604800, "reset_at": 1790575200}
        }
        """#
        let additional = (["Sample-Model"] + longLimitNames)
            .map { #"{"limit_name": "\#($0)", "rate_limit": \#(windows)}"# }
            .joined(separator: ", ")
        await stage.transport.answer(with: .codex(rateLimit: windows, additional: "[\(additional)]"), for: .codex)
        await stage.openPanel()
        stage.core.panelClosed()
        stage.clock.advance(by: 20 * 60)
        await stage.transport.answer(with: .timeout, for: .cursor)
        await stage.openPanel()
    }
}

extension Scenario {
    /// «Restablecimientos disponibles»: the Codex account holds 3 banked
    /// resets, so its card shows the count next to its name.
    public static let bankedResets = Scenario("bankedResets", "Restablecimientos disponibles") { stage in
        await stage.transport.answer(with: .codex(
            rateLimit: #"""
            {
              "primary_window": {"used_percent": 12, "limit_window_seconds": 18000, "reset_at": 1790186400},
              "secondary_window": {"used_percent": 41, "limit_window_seconds": 604800, "reset_at": 1790575200}
            }
            """#,
            resetCredits: #"{"available_count": 3, "applicable_available_count": 3}"#
        ), for: .codex)
        await stage.openPanel()
    }
}

/// The fakes behind a scenario's usage core.
@MainActor
final class Stage {
    let clock = ManualClock(Samples.readingMoment)
    let transport = ControlledTransport()
    /// Each official app's sample session, with its plan where the app keeps
    /// one. Codex's plan comes in its sample response.
    let sessionReaders: [Provider: ControlledSessionReader] = [
        .claude: ControlledSessionReader(session: Samples.claudeSession),
        .codex: ControlledSessionReader(),
        .cursor: ControlledSessionReader(session: Samples.cursorSession),
    ]
    let core: UsageCore

    init(enabledProviders: Set<Provider> = Set(Provider.allCases), order: [Provider] = Provider.allCases) {
        core = UsageCore(
            claudeSessionReader: sessionReaders[.claude]!,
            codexSessionReader: sessionReaders[.codex]!,
            cursorSessionReader: sessionReaders[.cursor]!,
            transport: transport,
            clock: clock,
            // Keeps the scenarios' failures out of the system log.
            log: RecordingLog(),
            initialEnabledProviders: enabledProviders,
            initialOrder: order
        )
    }

    func answerEverySession(with reading: SessionReading) async {
        for reader in sessionReaders.values {
            await reader.answer(with: reading)
        }
    }

    /// Opens the panel and waits for the queries of `providers` to finish.
    /// The others may be held by the transport.
    func openPanel(waitingFor providers: [Provider]? = nil) async {
        core.panelOpened()
        for provider in providers ?? Provider.allCases.filter({ core.enabledProviders.contains($0) }) {
            await core.queriesFinished(of: provider)
        }
    }
}

#endif
