# Uzzy

Uzzy shows the subscription quotas of AI services and when they reset.

## Language

**Copy**:
Any text a person reads about Uzzy: the app, the uzzy.app site, the README and the social images. The Spanish and English terms below apply to all of it.
Marketing copy (the site, the README, the social images and the repo description) says «AI usage limits», without «subscription». While the list of providers is closed, no copy claims coverage beyond it with «every» or «all» about providers or usage limits; it names Claude, Codex and Cursor instead. Counting the closed list is fine, e.g. «one, two or all three».
_Avoid_: Treating marketing text as exempt from the glossary; «subscription» in marketing copy; «every provider», «every usage limit», «all your limits».

**Subscription quota**:
A usage limit a provider applies to a subscription over a given period. Distinct from monetary spend and from billed API consumption.
In Spanish copy it is a «límite de uso»; in English copy, a «usage limit», shortened to «limit» once the text has said «usage limit» and it cannot be read as the monthly spend limit (see **Usage credits**).
_Avoid_: Balance, credits, consumption (without saying what is measured); «quota» in English copy; in Spanish, «cuota» (reads as a fee).

**Used quota**:
The part of a subscription quota already consumed within its period. In Spanish copy it is «usado»; in English copy, «used».
_Avoid_: Spend, cost; in Spanish, «consumido», «gastado».

**Remaining quota**:
The part of a subscription quota still available within its period. In Spanish copy it is «restante»; in English copy, «left», as Codex shows it.
_Avoid_: Available money, balance; in English, «remaining»; in Spanish, «disponible» (already means the data is present; the one exception is «restablecimiento disponible», see **Banked reset**), «libre».

**Reset**:
The moment, given by the provider, when a subscription quota renews. In Spanish copy it is «reinicio»; in English copy, «resets», e.g. «Resets today, 14:42».
_Avoid_: Top-up, session renewal.

**Banked reset**:
A reset the provider grants an account, which the person can redeem in the provider's app to refill quota windows. It belongs to the account, not to a quota. In Spanish copy it is a «restablecimiento disponible»; in English copy, a «reset available», Codex's own wording.
_Avoid_: Reset (the moment a quota renews), credits, spend; in Spanish, «reinicio», «crédito», «canjear».

**Last valid reading**:
A subscription quota's data from the last valid query for a specific account, together with the time of that query. After a failed refresh it is stale and does not confirm the current quota.
_Avoid_: Current quota (when it could not be refreshed), another account's data.

**Quota period**:
The interval a quota's usage and limit belong to. Quotas with different periods are independent even when they belong to the same provider.
_Avoid_: Calendar month (when it is a billing cycle), combined period.

**Quota bag**:
A share of a subscription the provider names and limits on its own, e.g. Cursor's «Cursor Models» and «Other Models» within one billing cycle. Bags of the same period are still separate quotas.
_Avoid_: Total, combined quota.

**Calculated value**:
A quota value derived from other valid data of that same quota, account, unit and period, rather than reported directly by the provider.
_Avoid_: Provider-reported value (when it is calculated), estimate (for an exact calculation).

**Session**:
The sign-in an official app (Claude Code, Codex CLI, Cursor) keeps on this Mac, which Uzzy reuses read-only to query quotas. It can be missing, expired (rejected by the provider), inaccessible (access denied by the user), in an unknown format, or without subscription quotas (e.g. Codex CLI signed in with an API key).
_Avoid_: Login, account (the account is the identity behind a session), the 5-hour quota period.

**Account**:
The provider identity behind a session, e.g. Claude Code's account UUID. Every last valid reading belongs to the account whose session produced it.
_Avoid_: User, profile, session (the session is how Uzzy reaches the account).

**Plan**:
The subscription an account is on, by the provider's own name, e.g. Claude's «Max», ChatGPT's «Plus» or Cursor's «Pro+». It belongs to the account, not to a quota, and gives context to the quotas: Uzzy shows it next to the card's title with the last valid reading it came with. Uzzy shows only plans the provider reports and Uzzy knows by name; it never guesses a plan, infers it from the quotas or shows the provider's raw identifier. In Spanish and English copy it is «plan».
_Avoid_: Tier, membership, subscription type (the providers' field names), account type.

**Uncertain identity**:
The state of a session whose account cannot be verified, e.g. because its identity is missing.
_Avoid_: Unknown account (as if it were a distinct account), anonymous session.

**Usage credits**:
Claude's pay-as-you-go consumption (formerly "extra usage"), billed at API rates after the subscription's included usage runs out, optionally capped by a **monthly spend limit** the person sets. Uzzy shows the amount spent this month and the limit, if any, in the provider's currency, as Claude does: «53,06 US$ de 40 US$ este mes», or «53,06 US$ este mes» without a limit. Spending can pass the limit and is shown as it is. It has no percentage, no used/remaining magnitude and no reset. The prepaid balance is not in the provider's response and is never shown or inferred. It is **not** a subscription quota; it sits among the quota rows as a deliberate exception. In Spanish copy it is «Créditos de uso»; in English copy, «Usage credits», Claude's own wording.
_Avoid_: Subscription quota, balance, a percentage of the limit, "extra usage" (as a label); in Spanish, «saldo», «cuota».

**Disabled provider**:
A provider the person has switched off in Uzzy. It has no card, and Uzzy does not read its session or query its quotas until the person switches it on again. In Spanish copy it is «desactivado» (the action, «desactivar»); in English copy, «turned off» (the action, «turn off»).
_Avoid_: Hidden card (suggests only a display change), missing session (a separate state); «hide» or «show» for switching a provider off or on.
