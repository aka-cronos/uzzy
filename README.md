<h1 align="center">Uzzy</h1>

<p align="center">
  <strong>Your Claude, Codex and Cursor subscription quotas, one click away in the macOS menu bar.</strong><br>
  How much you have used, how much is left and when each quota resets.
</p>

<p align="center">
  <a href="https://uzzy.app">uzzy.app</a> · <a href="https://github.com/aka-cronos/uzzy/releases/latest">Download</a>
</p>

<p align="center">
  <img alt="macOS 27" src="https://img.shields.io/badge/macOS-27-black?logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-black">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-blue"></a>
</p>

<p align="center">
  <img src="docs/images/app.jpg" width="420" alt="The Uzzy panel open from the menu bar, with one card each for Claude, Codex and Cursor and each account's plan next to its title. Every quota has its own bar, its used percentage and its reset time; the Claude card also shows the usage credits spent this month, and the Codex card a badge with its banked resets.">
</p>

## Why Uzzy

If you pay for more than one AI coding subscription, finding out how close you are to a limit means opening each provider's dashboard. Uzzy puts every quota in one panel, reusing the sessions Claude Code, Codex CLI and Cursor already keep on your Mac. There is nothing to sign in to and no API key to paste.

## Features

- **One card per provider.** A fixed menu bar icon opens a panel with a card for each enabled provider.
- **Every quota on its own.** Each quota («5 horas», «Semanal», «Cursor Models»…) gets its own bar, its reset in local time with a countdown, and the time of its last reading. Quotas are never combined into a single percentage.
- **Queries only while you look.** Uzzy reads the quotas when you open the panel (unless the last reading is under five minutes old), every five minutes while it stays open, and on demand with the refresh button. With the panel closed it makes no requests.
- **Honest failures.** If a provider fails, its card explains why (no session, expired session, offline, incompatible response…) and the others keep working. When a refresh fails, the card keeps the last valid reading and marks it as stale. Missing data is never shown as zero.
- **Native settings.** Choose used or remaining quota, and turn each provider on or off or change the order of the cards.
- **Your language.** The interface follows the system language: English or Spanish.

<p align="center">
  <img src="docs/images/settings.jpg" width="520" alt="The Uzzy Settings window: a Used / Left switch for the percentage on the cards, and the Claude, Codex and Cursor providers with buttons to reorder them and a switch to turn each one on or off.">
</p>

Open Settings with ⌘, from the panel; ⌘W closes it and ⌘Q quits. Your choices are remembered across launches, and a disabled provider has no card: Uzzy does not read its session or query its quotas.

## Supported providers

| Provider | Session it reuses | Quotas |
|---|---|---|
| **Claude** | Claude Code (the Keychain and `~/.claude.json`) | 5 hours, weekly, and weekly per model when the plan has them; also the usage credits spent this month and their monthly limit («Créditos de uso»), when usage credits are on |
| **Codex** | Codex CLI signed in with ChatGPT (`~/.codex/auth.json` or `$CODEX_HOME`) | 5 hours, weekly, any extra limit the plan has, and the account's banked resets |
| **Cursor** | Cursor (its local `state.vscdb`) | «Cursor Models» and «Other Models» for the billing cycle |

Each card also shows the account's plan next to its title, e.g. «Claude · Max», when the provider reports a plan Uzzy knows: Claude Code keeps it in its Keychain item, Codex sends it with the quotas and Cursor keeps it in `state.vscdb`.

Uzzy reads Claude Code's Keychain item through `/usr/bin/security`, the tool Claude Code writes it with. The item already trusts that tool, so macOS shows no Keychain prompt, even after Claude Code refreshes its token.

## Privacy

- Reuses, **read-only**, the sessions that already exist in Claude Code, Codex CLI and Cursor. It never asks for passwords, signs in, refreshes tokens or writes credentials.
- Only connects to `api.anthropic.com`, `chatgpt.com` and `api2.cursor.sh`. No telemetry and no server of its own.
- Quotas live only in memory; nothing is written to disk.
- Display magnitude, provider visibility and provider order preferences are stored in local `UserDefaults`; they contain no quota, token, email or account identifier.

## Install

Download `Uzzy.dmg` from [uzzy.app](https://uzzy.app) or [GitHub Releases](https://github.com/aka-cronos/uzzy/releases/latest), open it and drag Uzzy to Applications. It is signed with Developer ID and notarized by Apple, so it opens like any other app.

- Requires macOS 27.0 or later on Apple Silicon.
- Requires a signed-in session in Claude Code, Codex CLI (ChatGPT mode) and/or Cursor.

To open it at login, add it under System Settings → General → Login Items.

There are no automatic updates yet: to update, download the new `Uzzy.dmg`.

To build it yourself, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Disclaimer

The endpoints the app uses to read quotas are **internal and undocumented** by the providers. They may change or stop working without notice, and each person is responsible for using them within their provider's terms.

Uzzy is an independent project, not affiliated with, endorsed by or sponsored by the makers of Claude, Codex, ChatGPT or Cursor. All product names and trademarks belong to their respective owners.

## Acknowledgements

Endpoint research was informed by [OpenUsage](https://github.com/robinebers/openusage) (MIT) and [openai/codex](https://github.com/openai/codex) (Apache-2.0). No code was copied from either.

## License

[MIT](LICENSE). The agent skills under `.agents/skills/` are third-party MIT code; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), which also credits the background photo.
