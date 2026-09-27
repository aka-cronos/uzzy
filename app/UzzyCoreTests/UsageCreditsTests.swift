import Foundation
import Testing
import UzzyCore

/// Claude's usage credits («Créditos de uso»): the money spent on them this
/// month and the monthly spend limit, read from `extra_usage`. They are not a
/// subscription quota: no percentage, no magnitude and no reset.
@MainActor
struct UsageCreditsTests {
    let readingMoment = Samples.readingMoment
    let subscriptionQuotas = [
        Quota(
            period: .fiveHours,
            value: .percent(35, calculated: false),
            // 2026-09-23T17:00:00Z
            reset: .at(Date(timeIntervalSince1970: 1_790_182_800)),
            readAt: Samples.readingMoment
        ),
        Quota(
            period: .weekly,
            value: .percent(62, calculated: false),
            // 2026-09-25T09:00:00Z
            reset: .at(Date(timeIntervalSince1970: 1_790_326_800)),
            readAt: Samples.readingMoment
        ),
    ]

    /// The 5-hour and weekly windows of the sample, with `extraUsage` as the
    /// raw JSON of `extra_usage`, or without the key when it is nil.
    static func response(extraUsage: String?) -> String {
        """
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"}\
        \(extraUsage.map { ",\n  \"extra_usage\": \($0)" } ?? "")
        }
        """
    }

    static let overTheLimit = #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": 5306, "utilization": 132.65, "currency": "USD"}"#

    func openedPanel(claudeResponse: String, magnitude: QuotaMagnitude = .used) async -> UsageCore {
        let core = UsageCore(
            claudeSessionReader: SampleSessionReader(),
            codexSessionReader: NoSessionReader(),
            cursorSessionReader: NoSessionReader(),
            transport: SampleTransport(claudeResponse: Data(claudeResponse.utf8)),
            clock: FixedClock(readingMoment),
            initialMagnitude: magnitude
        )
        core.panelOpened()
        await core.queriesFinished()
        return core
    }

    func claudeQuotas(_ core: UsageCore) -> [Quota]? {
        guard case .quotas(let quotas) = core.state.cards.first(where: { $0.provider == .claude })?.content else {
            return nil
        }
        return quotas
    }

    /// The value of the usage-credits row of the Claude card, or nil when
    /// there is no row.
    func usageCredits(extraUsage: String?, magnitude: QuotaMagnitude = .used) async -> QuotaValue? {
        let core = await openedPanel(claudeResponse: Self.response(extraUsage: extraUsage), magnitude: magnitude)
        return claudeQuotas(core)?.first { $0.period == .usageCredits }?.value
    }

    func usd(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: "USD")
    }

    /// A panel whose first Claude reading has a usage-credits row, with a
    /// transport and a clock the test drives afterwards.
    func panelWithAUsageCreditsRow() async -> (UsageCore, ControlledTransport, ManualClock) {
        let clock = ManualClock(readingMoment)
        let transport = ControlledTransport()
        let core = UsageCore(
            claudeSessionReader: SampleSessionReader(),
            codexSessionReader: NoSessionReader(),
            cursorSessionReader: NoSessionReader(),
            transport: transport,
            clock: clock
        )
        await transport.answer(with: .json(Self.response(extraUsage: Self.overTheLimit)), for: .claude)
        core.panelOpened()
        await core.queriesFinished()
        return (core, transport, clock)
    }

    @Test func theSampleResponseWithUsageCreditsDisabledShowsNoRow() async {
        let core = await openedPanel(claudeResponse: String(decoding: Samples.claudeUsageResponse, as: UTF8.self))

        #expect(claudeQuotas(core) == subscriptionQuotas)
    }

    @Test func spendingPastTheMonthlyLimitIsShownAsItIs() async {
        let core = await openedPanel(claudeResponse: Self.response(extraUsage: Self.overTheLimit))

        #expect(claudeQuotas(core) == subscriptionQuotas + [
            Quota(period: .usageCredits, value: .spend(usd("53.06"), limit: usd("40")), reset: nil, readAt: readingMoment),
        ])
    }

    @Test(arguments: [
        #"{"is_enabled": true, "used_credits": 5306, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": null, "used_credits": 5306, "utilization": null, "currency": "USD"}"#,
    ])
    func withoutAMonthlyLimitOnlyTheSpendIsShown(extraUsage: String) async {
        #expect(await usageCredits(extraUsage: extraUsage) == .spend(usd("53.06"), limit: nil))
    }

    @Test func nothingSpentYetIsZero() async {
        let extraUsage = #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": 0, "utilization": null, "currency": "USD"}"#

        #expect(await usageCredits(extraUsage: extraUsage) == .spend(usd("0"), limit: usd("40")))
    }

    @Test(arguments: [
        #"{"is_enabled": true, "monthly_limit": 0, "used_credits": 0, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": 0, "used_credits": 5306, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": 0.0, "used_credits": 0, "currency": "USD"}"#,
    ])
    func aZeroMonthlyLimitShowsNoRow(extraUsage: String) async {
        #expect(await usageCredits(extraUsage: extraUsage) == nil)
    }

    @Test(arguments: [
        // Yen have no minor unit, and Bahraini dinars have three digits.
        ("JPY", "5306", "4000", 5306 as Decimal, 4000 as Decimal),
        ("BHD", "5306", "4000", Decimal(string: "5.306")!, 4 as Decimal),
        ("EUR", "5306.0", "4000", Decimal(string: "53.06")!, 40 as Decimal),
    ])
    func amountsAreInTheMinorUnitsOfTheirCurrency(currency: String, used: String, limit: String, spent: Decimal, cap: Decimal) async {
        let extraUsage = #"{"is_enabled": true, "monthly_limit": \#(limit), "used_credits": \#(used), "currency": "\#(currency)"}"#

        #expect(await usageCredits(extraUsage: extraUsage) == .spend(
            Money(amount: spent, currency: currency), limit: Money(amount: cap, currency: currency)
        ))
    }

    @Test func utilizationIsNeverRead() async {
        let extraUsage = #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": 5306, "utilization": "not a number", "currency": "USD"}"#

        #expect(await usageCredits(extraUsage: extraUsage) == .spend(usd("53.06"), limit: usd("40")))
    }

    @Test func theAmountsDoNotChangeWithTheMagnitude() async {
        let extraUsage = Self.overTheLimit

        #expect(await usageCredits(extraUsage: extraUsage, magnitude: .remaining) == .spend(usd("53.06"), limit: usd("40")))
    }

    @Test(arguments: [
        nil,
        "null",
        #""enabled""#,
        "[]",
        #"{"monthly_limit": 4000, "used_credits": 5306, "currency": "USD"}"#,
        #"{"is_enabled": null, "monthly_limit": 4000, "used_credits": 5306, "currency": "USD"}"#,
        #"{"is_enabled": false, "monthly_limit": 4000, "used_credits": 5306, "currency": "USD"}"#,
        #"{"is_enabled": 1, "monthly_limit": 4000, "used_credits": 5306, "currency": "USD"}"#,
        #"{"is_enabled": "true", "monthly_limit": 4000, "used_credits": 5306, "currency": "USD"}"#,
    ])
    func withoutEnabledUsageCreditsThereIsNoRow(extraUsage: String?) async {
        #expect(await usageCredits(extraUsage: extraUsage) == nil)
    }

    @Test(arguments: [
        #"{"is_enabled": true, "monthly_limit": 4000, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": null, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": -1, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": 5306.5, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": "5306", "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": true, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": 1e400, "currency": "USD"}"#,
    ])
    func withoutAValidSpendThereIsNoRow(extraUsage: String) async {
        #expect(await usageCredits(extraUsage: extraUsage) == nil)
    }

    @Test(arguments: [
        #"{"is_enabled": true, "monthly_limit": -4000, "used_credits": 5306, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": 4000.5, "used_credits": 5306, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": "4000", "used_credits": 5306, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": [4000], "used_credits": 5306, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": 1e400, "used_credits": 5306, "currency": "USD"}"#,
    ])
    func aMalformedMonthlyLimitShowsNoRowRatherThanNoLimit(extraUsage: String) async {
        #expect(await usageCredits(extraUsage: extraUsage) == nil)
    }

    @Test(arguments: [
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": 5306}"#,
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": 5306, "currency": null}"#,
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": 5306, "currency": "usd"}"#,
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": 5306, "currency": "US"}"#,
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": 5306, "currency": "ABC"}"#,
        // ISO 4217's codes for "no currency" and for testing.
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": 5306, "currency": "XXX"}"#,
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": 5306, "currency": "XTS"}"#,
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": 5306, "currency": 840}"#,
    ])
    func withoutAKnownCurrencyThereIsNoRow(extraUsage: String) async {
        #expect(await usageCredits(extraUsage: extraUsage) == nil)
    }

    @Test(arguments: [
        #""enabled""#,
        #"{"is_enabled": "true", "monthly_limit": 4000, "used_credits": 5306, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": 1e400, "used_credits": 5306, "currency": "USD"}"#,
        #"{"is_enabled": true, "monthly_limit": 4000, "used_credits": [5306], "currency": 840}"#,
    ])
    func malformedUsageCreditsNeverChangeTheSubscriptionQuotas(extraUsage: String) async {
        let core = await openedPanel(claudeResponse: Self.response(extraUsage: extraUsage))

        #expect(claudeQuotas(core) == subscriptionQuotas)
    }

    @Test func theRowHasNoResetWhileTheSubscriptionQuotasKeepTheirs() async {
        let core = await openedPanel(claudeResponse: Self.response(extraUsage: Self.overTheLimit))

        // The provider sends no reset for usage credits, and none is inferred.
        #expect(claudeQuotas(core)?.map(\.reset) == [
            .at(Date(timeIntervalSince1970: 1_790_182_800)),
            .at(Date(timeIntervalSince1970: 1_790_326_800)),
            nil,
        ])
    }

    @Test func theRowFollowsThePerModelLimits() async {
        let core = await openedPanel(claudeResponse: """
        {
          "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
          "extra_usage": \(Self.overTheLimit),
          "limits": [
            {"kind": "weekly_scoped", "percent": 20.0, "resets_at": "2026-09-25T09:00:00.000000+00:00",
             "scope": {"model": {"display_name": "Fable"}}}
          ]
        }
        """)

        #expect(claudeQuotas(core)?.map(\.period) == [.fiveHours, .weekly, .limit("Fable", .weekly), .usageCredits])
    }

    @Test func aReadingWithoutTheRowRemovesIt() async {
        let (core, transport, clock) = await panelWithAUsageCreditsRow()
        #expect(claudeQuotas(core)?.last?.period == .usageCredits)

        await transport.answer(with: .json(Self.response(extraUsage: #"{"is_enabled": false}"#)), for: .claude)
        clock.advance(by: 5 * 60)
        await core.queriesFinished()

        #expect(claudeQuotas(core)?.map(\.period) == [.fiveHours, .weekly])
    }

    @Test func aFailedRefreshKeepsTheRowStaleWithItsReadingTime() async {
        let (core, transport, clock) = await panelWithAUsageCreditsRow()

        await transport.answer(with: .networkError, for: .claude)
        clock.advance(by: 5 * 60)
        await core.queriesFinished()

        guard case .stale(let quotas, failure: .offline) = core.state.cards.first(where: { $0.provider == .claude })?.content else {
            Issue.record("Expected the stale reading")
            return
        }
        #expect(quotas.last == Quota(
            period: .usageCredits, value: .spend(usd("53.06"), limit: usd("40")), reset: nil, readAt: readingMoment, isStale: true
        ))
    }
}
