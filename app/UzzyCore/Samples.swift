import Foundation

// Fictional data for the tests and the debug scenarios; never in a Release build.
#if DEBUG

/// Sanitized sample responses, in the formats observed while validating the
/// sources. They contain no real personal data.
public enum Samples {
    /// A fictional session of the sample account.
    public static let session = Session(accessToken: "sample-token", accountID: "sample-account")

    /// The sample session as Claude Code keeps it, on the Max plan.
    public static let claudeSession = Session(accessToken: "sample-token", accountID: "sample-account", plan: "max")

    /// The sample session as Cursor keeps it, on the Pro+ plan.
    public static let cursorSession = Session(accessToken: "sample-token", accountID: "sample-account", plan: "pro_plus")

    /// Reading moment consistent with the sample responses: 2026-09-23T14:32:00Z.
    public static let readingMoment = Date(timeIntervalSince1970: 1_790_173_920)

    /// Claude's `GET /api/oauth/usage`. `limits[]` repeats both windows, as the
    /// real response does. Includes fields that are ignored (opaque names and
    /// empty per-model limits) and a disabled `extra_usage`, which shows no
    /// usage credits.
    public static let claudeUsageResponse = Data(#"""
    {
      "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
      "seven_day": {"utilization": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00"},
      "seven_day_oauth_apps": null,
      "seven_day_opus": null,
      "seven_day_sonnet": null,
      "iguana_necktie": null,
      "extra_usage": {"is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null},
      "limits": [
        {"kind": "session", "percent": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00", "scope": null},
        {"kind": "weekly_all", "percent": 62.0, "resets_at": "2026-09-25T09:00:00.000000+00:00", "scope": null}
      ]
    }
    """#.utf8)

    /// Codex's `GET /backend-api/wham/usage` for a ChatGPT session, on the
    /// Plus plan. Includes fields that are ignored (identifiers, credits,
    /// `spend_control` and `model_usage`).
    public static let codexUsageResponse = Data(#"""
    {
      "user_id": "user-sample",
      "account_id": "sample-account",
      "email": "sample@example.com",
      "plan_type": "plus",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {"used_percent": 12, "limit_window_seconds": 18000, "reset_after_seconds": 12480, "reset_at": 1790186400},
        "secondary_window": {"used_percent": 41, "limit_window_seconds": 604800, "reset_after_seconds": 401280, "reset_at": 1790575200}
      },
      "code_review_rate_limit": null,
      "additional_rate_limits": null,
      "model_usage": {"sample-model": {"available": true, "available_at": null, "credits_would_enable": false}},
      "credits": {
        "has_credits": true,
        "unlimited": false,
        "overage_limit_reached": false,
        "balance": "0",
        "approx_local_messages": [0, 0],
        "approx_cloud_messages": [0, 0]
      },
      "spend_control": {"reached": false, "individual_limit": null},
      "rate_limit_reached_type": null,
      "promo": null,
      "rate_limit_reset_credits": {"available_count": 0, "applicable_available_count": 0}
    }
    """#.utf8)

    public static let cursorPlanResponse = Data(#"{"planInfo":{"includedUsagePeriod":"INCLUDED_USAGE_PERIOD_MONTHLY"}}"#.utf8)

    /// Cursor's `POST /aiserver.v1.DashboardService/GetCurrentPeriodUsage`.
    /// The billing cycle runs from 2026-09-10 to 2026-10-10 (UTC). Includes
    /// fields ignored for legacy plans: `totalPercentUsed`, which contradicts
    /// the separate bags, the amounts in cents and the text messages.
    public static let cursorUsageResponse = Data(#"""
    {
      "billingCycleStart": "1788998400000",
      "billingCycleEnd": "1791590400000",
      "planUsage": {
        "totalSpend": 2800,
        "includedSpend": 2800,
        "remaining": 17200,
        "limit": 20000,
        "remainingBonus": false,
        "bonusTooltip": "Sample bonus text",
        "autoPercentUsed": 18.5,
        "apiPercentUsed": 42.75,
        "totalPercentUsed": 3.1
      },
      "spendLimitUsage": {"limitType": "user"},
      "displayThreshold": 50,
      "enabled": true,
      "displayMessage": "You've used 14% of your included usage",
      "autoModelSelectedDisplayMessage": "Sample message",
      "namedModelSelectedDisplayMessage": "Sample message",
      "autoBucketModels": ["sample-model"]
    }
    """#.utf8)

    /// Antigravity's `POST /v1internal:loadCodeAssist`: the generic current
    /// tier, the paid tier that names the plan (Google AI Pro) and the
    /// project the quota summary is asked for. Fictional project ID.
    public static let antigravityAccountResponse = Data(#"""
    {
      "currentTier": {"id": "free-tier", "name": "Antigravity", "description": "Sample tier"},
      "allowedTiers": [{"id": "free-tier", "name": "Antigravity", "isDefault": true}],
      "cloudaicompanionProject": "sample-project",
      "gcpManaged": false,
      "paidTier": {
        "id": "g1-pro-tier",
        "name": "Google AI Pro",
        "availableCredits": [{"creditType": "GOOGLE_ONE_AI", "minimumCreditAmountForUsage": "50"}]
      }
    }
    """#.utf8)

    /// Antigravity's `POST /v1internal:retrieveUserQuotaSummary`, read at
    /// 2026-09-23T14:32:00Z. Each group sends its weekly bucket before its
    /// 5-hour one. Gemini is in use; Claude and GPT is untouched, so its
    /// resets are the reading moment plus each window's length; Gemini 4
    /// Argon has only a weekly limit.
    public static let antigravityQuotaResponse = Data(#"""
    {
      "groups": [
        {
          "displayName": "Gemini Models",
          "description": "Models within this group: Gemini Flash, Gemini Pro",
          "buckets": [
            {"bucketId": "gemini-weekly", "displayName": "Weekly Limit Remaining", "window": "weekly",
             "resetTime": "2026-09-28T12:32:00Z", "remainingFraction": 0.64},
            {"bucketId": "gemini-5h", "displayName": "Five Hour Limit Remaining", "window": "5h",
             "resetTime": "2026-09-23T18:17:00Z", "remainingFraction": 0.96}
          ]
        },
        {
          "displayName": "Claude and GPT models",
          "description": "Models within this group: Claude Opus, Claude Sonnet, GPT-OSS",
          "buckets": [
            {"bucketId": "3p-weekly", "displayName": "Weekly Limit Remaining", "window": "weekly",
             "resetTime": "2026-09-30T14:32:00Z", "remainingFraction": 1},
            {"bucketId": "3p-5h", "displayName": "Five Hour Limit Remaining", "window": "5h",
             "resetTime": "2026-09-23T19:32:00Z", "remainingFraction": 1}
          ]
        },
        {
          "displayName": "Gemini 4 Argon",
          "description": "Sample description",
          "buckets": [
            {"bucketId": "gemini-argon-wtu-weekly", "displayName": "Gemini 4 Argon Weekly Limit", "window": "weekly",
             "resetTime": "2026-09-29T08:00:00Z", "remainingFraction": 0.88}
          ]
        }
      ],
      "description": "Sample description"
    }
    """#.utf8)

    /// Antigravity's local daemon `GetUserStatus` response: carries the
    /// account email and `userTier` (`g1-pro-tier`), while `planStatus`
    /// carries a generic plan name that the adapter ignores.
    public static let antigravityDaemonStatusResponse = Data(#"""
    {
      "userStatus": {
        "email": "sample@example.com",
        "name": "Sample User",
        "userTier": {
          "id": "g1-pro-tier",
          "name": "Google AI Pro",
          "availableCredits": [{"creditType": "GOOGLE_ONE_AI", "minimumCreditAmountForUsage": "50"}]
        },
        "planStatus": {
          "planInfo": {"planName": "Pro", "teamsTier": "TEAMS_TIER_PRO"}
        }
      }
    }
    """#.utf8)

    /// Antigravity's local daemon `RetrieveUserQuotaSummary` response: the
    /// same groups and buckets as Cloud Code, wrapped in `response`.
    public static let antigravityDaemonQuotaResponse = Data(#"""
    {
      "response": {
        "groups": [
          {
            "displayName": "Gemini Models",
            "description": "Models within this group: Gemini Flash, Gemini Pro",
            "buckets": [
              {"bucketId": "gemini-weekly", "displayName": "Weekly Limit Remaining", "window": "weekly",
               "resetTime": "2026-09-28T12:32:00Z", "remainingFraction": 0.64},
              {"bucketId": "gemini-5h", "displayName": "Five Hour Limit Remaining", "window": "5h",
               "resetTime": "2026-09-23T18:17:00Z", "remainingFraction": 0.96}
            ]
          },
          {
            "displayName": "Claude and GPT models",
            "description": "Models within this group: Claude Opus, Claude Sonnet, GPT-OSS",
            "buckets": [
              {"bucketId": "3p-weekly", "displayName": "Weekly Limit Remaining", "window": "weekly",
               "resetTime": "2026-09-30T14:32:00Z", "remainingFraction": 1},
              {"bucketId": "3p-5h", "displayName": "Five Hour Limit Remaining", "window": "5h",
               "resetTime": "2026-09-23T19:32:00Z", "remainingFraction": 1}
            ]
          },
          {
            "displayName": "Gemini 4 Argon",
            "description": "Sample description",
            "buckets": [
              {"bucketId": "gemini-argon-wtu-weekly", "displayName": "Gemini 4 Argon Weekly Limit", "window": "weekly",
               "resetTime": "2026-09-29T08:00:00Z", "remainingFraction": 0.88}
            ]
          }
        ],
        "description": "Sample description"
      }
    }
    """#.utf8)
}

#endif
