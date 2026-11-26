import Foundation
import Testing
import UzzyCore

/// Presentation rules of a quota, through the usage core: used or remaining
/// quota, calculated values, missing and uninterpretable data, and resets.
@MainActor
struct QuotaPresentationTests {
    let readingMoment = Samples.readingMoment
    // 2026-09-23T17:00:00Z and 2026-09-25T09:00:00Z
    let fiveHourReset = Date(timeIntervalSince1970: 1_790_182_800)
    let weeklyReset = Date(timeIntervalSince1970: 1_790_326_800)

    func openedPanel(claudeResponse: String = Self.sampleResponse, clock: (any WallClock)? = nil) async -> UsageCore {
        let core = UsageCore(
            claudeSessionReader: SampleSessionReader(),
            codexSessionReader: NoSessionReader(),
            cursorSessionReader: NoSessionReader(),
            transport: SampleTransport(claudeResponse: Data(claudeResponse.utf8)),
            clock: clock ?? FixedClock(readingMoment)
        )
        core.panelOpened()
        await core.queriesFinished()
        return core
    }

    static let sampleResponse = String(decoding: Samples.claudeUsageResponse, as: UTF8.self)

    func claudeQuotas(_ core: UsageCore) -> [Quota]? {
        guard case .quotas(let quotas) = core.state.cards.first(where: { $0.provider == .claude })?.content else {
            return nil
        }
        return quotas
    }

    @Test func usedQuotaIsShownByDefault() async {
        let core = await openedPanel()

        #expect(core.state.magnitude == .used)
        #expect(claudeQuotas(core)?.map(\.value) == [.percent(35, calculated: false), .percent(62, calculated: false)])
    }

    @Test func savedMagnitudeCanBeUsedWhenCreatingTheCore() async {
        let core = UsageCore(
            claudeSessionReader: SampleSessionReader(),
            codexSessionReader: NoSessionReader(),
            cursorSessionReader: NoSessionReader(),
            transport: SampleTransport(),
            clock: FixedClock(readingMoment),
            initialMagnitude: .remaining
        )
        core.panelOpened()
        await core.queriesFinished()

        #expect(core.state.magnitude == .remaining)
        #expect(claudeQuotas(core)?.map(\.value) == [.percent(65, calculated: true), .percent(38, calculated: true)])
    }

    @Test func remainingQuotaIsCalculatedFromTheUsedQuotaOfEachQuota() async {
        let core = await openedPanel()

        core.show(.remaining)

        #expect(core.state.magnitude == .remaining)
        #expect(claudeQuotas(core) == [
            Quota(period: .fiveHours, value: .percent(65, calculated: true), reset: .at(fiveHourReset), readAt: readingMoment),
            Quota(period: .weekly, value: .percent(38, calculated: true), reset: .at(weeklyReset), readAt: readingMoment),
        ])
    }

    @Test func switchingBackShowsTheUsedQuotaAgain() async {
        let core = await openedPanel()

        core.show(.remaining)
        core.show(.used)

        #expect(core.state.magnitude == .used)
        #expect(claudeQuotas(core)?.map(\.value) == [.percent(35, calculated: false), .percent(62, calculated: false)])
    }

    @Test(arguments: [120.0, -5.0, 100.5])
    func aPercentageOutsideZeroToHundredIsUninterpretableAndNotClamped(utilization: Double) async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": \(utilization), "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"}
        }
        """)

        #expect(claudeQuotas(core)?.map(\.value) == [.uninterpretable, .percent(62, calculated: false)])
    }

    @Test func noRemainingQuotaIsCalculatedFromAnUninterpretablePercentage() async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": 120.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"}
        }
        """)

        core.show(.remaining)

        #expect(claudeQuotas(core)?.map(\.value) == [.uninterpretable, .percent(38, calculated: true)])
    }

    @Test func theBoundariesZeroAndHundredAreValid() async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": 0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 100, "resets_at": "2026-09-25T09:00:00.000000+00:00"}
        }
        """)

        core.show(.remaining)

        #expect(claudeQuotas(core)?.map(\.value) == [.percent(100, calculated: true), .percent(0, calculated: true)])
    }

    @Test(arguments: [
        #""seven_day": null"#,
        #""seven_day": {"utilization": null, "resets_at": null}"#,
        #""other": null"#,
    ])
    func aMissingQuotaIsUnavailableAndTheOtherStaysVisible(sevenDay: String) async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          \(sevenDay)
        }
        """)

        #expect(claudeQuotas(core) == [
            Quota(period: .fiveHours, value: .percent(35, calculated: false), reset: .at(fiveHourReset), readAt: readingMoment),
            Quota(period: .weekly, value: .unavailable, reset: .unknown, readAt: readingMoment),
        ])
    }

    @Test func aMissingQuotaIsNeverShownAsZeroNorAsFullyRemaining() async {
        let core = await openedPanel(claudeResponse: """
        {"five_hour": null, "seven_day": {"utilization": 62.0, "resets_at": null}}
        """)

        core.show(.remaining)

        #expect(claudeQuotas(core)?.map(\.value) == [.unavailable, .percent(38, calculated: true)])
    }

    @Test func noQuotaInTheResponseIsNotTakenAsEvidenceAboutThePlan() async {
        let core = await openedPanel(claudeResponse: #"{"five_hour": null, "seven_day": null}"#)

        #expect(claudeQuotas(core)?.map(\.value) == [.unavailable, .unavailable])
    }

    @Test(arguments: [
        #""resets_at": null"#,
        #""resets_at": "mañana""#,
        #""other": null"#,
        #""resets_at": "9999-12-31T23:59:59Z""#,
    ])
    func aResetWithoutAValidDateIsUnknownAndTheFigureIsKept(resetsAt: String) async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": 35.0, \(resetsAt)},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"}
        }
        """)

        #expect(claudeQuotas(core)?.first == Quota(
            period: .fiveHours, value: .percent(35, calculated: false), reset: .unknown, readAt: readingMoment
        ))
    }

    @Test func aResetThatPassesWithoutANewReadingIsPendingConfirmationAndItsFigureStale() async {
        let clock = ManualClock(readingMoment)
        let core = await openedPanel(clock: clock)
        // No query runs while the panel is closed, so no new reading arrives.
        core.panelClosed()

        clock.move(to: fiveHourReset)

        // The figure is kept as it was, never set to zero.
        #expect(claudeQuotas(core) == [
            Quota(
                period: .fiveHours,
                value: .percent(35, calculated: false),
                reset: .pendingConfirmation,
                readAt: readingMoment,
                isStale: true
            ),
            Quota(period: .weekly, value: .percent(62, calculated: false), reset: .at(weeklyReset), readAt: readingMoment),
        ])
    }

    @Test func aResetStillAheadKeepsItsDate() async {
        let clock = ManualClock(readingMoment)
        let core = await openedPanel(clock: clock)

        clock.move(to: fiveHourReset.addingTimeInterval(-1))

        #expect(claudeQuotas(core)?.first?.reset == .at(fiveHourReset))
    }

    @Test func perModelLimitsAreShownOnlyWhenSentExplicitlyWithData() async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "seven_day_sonnet": {"utilization": 12.5, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "seven_day_opus": {"utilization": null, "resets_at": null}
        }
        """)

        #expect(claudeQuotas(core) == [
            Quota(period: .fiveHours, value: .percent(35, calculated: false), reset: .at(fiveHourReset), readAt: readingMoment),
            Quota(period: .weekly, value: .percent(62, calculated: false), reset: .at(weeklyReset), readAt: readingMoment),
            Quota(period: .limit("Sonnet", .weekly), value: .percent(12.5, calculated: false), reset: .at(weeklyReset), readAt: readingMoment),
        ])
    }

    @Test func perModelLimitsAreAlsoReadFromTheScopedEntriesOfLimits() async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "seven_day_sonnet": null,
          "limits": [
            {"kind": "weekly_scoped", "percent": 20.0, "resets_at": "2026-09-25T09:00:00.000000+00:00",
             "scope": {"model": {"display_name": "Fable"}}},
            {"kind": "weekly_scoped", "percent": null, "resets_at": null,
             "scope": {"model": {"display_name": "Opus"}}}
          ]
        }
        """)

        #expect(claudeQuotas(core)?.map(\.period) == [.fiveHours, .weekly, .limit("Fable", .weekly)])
        #expect(claudeQuotas(core)?.last?.value == .percent(20, calculated: false))
    }

    @Test func everyCopyOfAPerModelLimitCountsWhereverItAppears() async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "seven_day_sonnet": {"utilization": 12.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "limits": [
            {"kind": "weekly_scoped", "percent": 20.0, "resets_at": "2026-09-25T09:00:00.000000+00:00",
             "scope": {"model": {"display_name": "Fable"}}},
            {"kind": "weekly_scoped", "percent": 12.0, "resets_at": "2026-09-25T09:00:00.000000+00:00",
             "scope": {"model": {"display_name": "Sonnet"}}},
            {"kind": "session", "percent": 30.0, "resets_at": "2026-09-23T17:00:00.000000+00:00",
             "scope": {"model": {"display_name": "Fable"}}},
            {"kind": "weekly_scoped", "percent": 70.0, "resets_at": "2026-09-25T09:00:00.000000+00:00",
             "scope": {"model": {"display_name": "Fable"}}}
          ]
        }
        """)

        #expect(claudeQuotas(core) == [
            Quota(period: .fiveHours, value: .percent(35, calculated: false), reset: .at(fiveHourReset), readAt: readingMoment),
            Quota(period: .weekly, value: .percent(62, calculated: false), reset: .at(weeklyReset), readAt: readingMoment),
            Quota(period: .limit("Sonnet", .weekly), value: .percent(12, calculated: false), reset: .at(weeklyReset), readAt: readingMoment),
            // Its two weekly copies disagree; the session entry is another quota.
            Quota(period: .limit("Fable", .weekly), value: .uninterpretable, reset: .at(weeklyReset), readAt: readingMoment),
        ])
    }

    @Test func aQuotaReportedOnlyInLimitsIsShown() async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": null,
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "limits": [{"kind": "session", "percent": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"}]
        }
        """)

        #expect(claudeQuotas(core)?.first == Quota(
            period: .fiveHours, value: .percent(35, calculated: false), reset: .at(fiveHourReset), readAt: readingMoment
        ))
    }

    @Test(arguments: [35.0, 35.8])
    func copiesOfAQuotaThatAgreeShowItsFigureOnce(sessionPercent: Double) async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "limits": [{"kind": "session", "percent": \(sessionPercent), "resets_at": "2026-09-23T17:00:00.000000+00:00"}]
        }
        """)

        #expect(claudeQuotas(core)?.map(\.value) == [.percent(35, calculated: false), .percent(62, calculated: false)])
    }

    @Test func contradictoryFiguresOfAQuotaAreUninterpretableAndTheOtherStaysVisible() async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "limits": [
            {"kind": "session", "percent": 60.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
            {"kind": "weekly_all", "percent": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"}
          ]
        }
        """)

        #expect(claudeQuotas(core)?.map(\.value) == [.uninterpretable, .percent(62, calculated: false)])

        core.show(.remaining)

        #expect(claudeQuotas(core)?.map(\.value) == [.uninterpretable, .percent(38, calculated: true)])
    }

    @Test func aCopyOutsideZeroToHundredMakesTheQuotaUninterpretable() async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "limits": [{"kind": "session", "percent": 135.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"}]
        }
        """)

        #expect(claudeQuotas(core)?.first?.value == .uninterpretable)
    }

    @Test func contradictoryResetsOfAQuotaAreUnknownAndTheFigureIsKept() async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "limits": [{"kind": "session", "percent": 35.0, "resets_at": "2026-09-23T19:00:00.000000+00:00"}]
        }
        """)

        #expect(claudeQuotas(core)?.first == Quota(
            period: .fiveHours, value: .percent(35, calculated: false), reset: .unknown, readAt: readingMoment
        ))
    }

    @Test func onlyTheUsageCreditAmountsAreShownNeverSpendOrOpaqueFields() async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "iguana_necktie": {"utilization": 80.0, "resets_at": "2026-09-24T00:00:00.000000+00:00"},
          "extra_usage": {"is_enabled": true, "monthly_limit": 5000, "used_credits": 1200, "utilization": 24.0, "currency": "USD"},
          "spend": {"amount": 9900, "currency": "EUR"}
        }
        """)

        // The usage credits spent and their monthly limit, from `extra_usage` alone.
        #expect(claudeQuotas(core) == [
            Quota(period: .fiveHours, value: .percent(35, calculated: false), reset: .at(fiveHourReset), readAt: readingMoment),
            Quota(period: .weekly, value: .percent(62, calculated: false), reset: .at(weeklyReset), readAt: readingMoment),
            Quota(
                period: .usageCredits,
                value: .spend(Money(amount: 12, currency: "USD"), limit: Money(amount: 50, currency: "USD")),
                reset: nil,
                readAt: readingMoment
            ),
        ])
    }
}
