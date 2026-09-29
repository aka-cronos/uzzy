<h1 align="center">Uzzy</h1>

<p align="center">
  <strong>Your Claude, Codex and Cursor subscription quotas, one click away in the macOS menu bar.</strong><br>
  How much you have used, how much is left and when each quota resets.
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

> [!NOTE]
> Uzzy is in development. The MVP is specified in [#11](https://github.com/aka-cronos/uzzy/issues/11), and there are no prebuilt releases yet: you [build it yourself](#install). The app's interface follows the system language: English or Spanish.

## Why Uzzy

If you pay for more than one AI coding subscription, finding out how close you are to a limit means opening each provider's dashboard. Uzzy puts every quota in one panel, reusing the sessions Claude Code, Codex CLI and Cursor already keep on your Mac. There is nothing to sign in to and no API key to paste.

## Features

- **One card per provider.** A fixed menu bar icon opens a panel with a card for each enabled provider.
- **Every quota on its own.** Each quota («5 horas», «Semanal», «Cursor Models»…) gets its own bar, its reset in local time with a countdown, and the time of its last reading. Quotas are never combined into a single percentage.
- **Queries only while you look.** Uzzy reads the quotas when you open the panel (unless the last reading is under five minutes old), every five minutes while it stays open, and on demand with the refresh button. With the panel closed it makes no requests.
- **Honest failures.** If a provider fails, its card explains why (no session, expired session, offline, incompatible response…) and the others keep working. When a refresh fails, the card keeps the last valid reading and marks it as stale. Missing data is never shown as zero.
- **Native settings.** Choose used or remaining quota, and turn each provider on or off or change the order of the cards.

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

### Requirements

- macOS 27 on Apple Silicon.
- Xcode 27 to build.
- A signed-in session in Claude Code, Codex CLI (ChatGPT mode) and/or Cursor.

No Apple Developer account is needed: by default the app is signed ad hoc ("Sign to Run Locally"). To sign with your own team, see [Signing](CONTRIBUTING.md#signing).

### Build and install

To keep Uzzy running day to day, build it in Release and copy it to `/Applications`. From the repo root you can paste the whole block; Terminal runs the three commands in order.

```sh
# Compile a Release build into the local `build/` folder
xcodebuild build \
  -project app/Uzzy.xcodeproj \
  -scheme Uzzy \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build

# Install the app next to the rest of your applications
cp -R build/Build/Products/Release/Uzzy.app /Applications/

# Launch the installed copy
open /Applications/Uzzy.app
```

To open it at login, add it under System Settings → General → Login Items.

## Development

### Build and test

```sh
xcodebuild test -project app/Uzzy.xcodeproj -scheme Uzzy -destination 'platform=macOS,arch=arm64'
xcodebuild build -project app/Uzzy.xcodeproj -scheme Uzzy -destination 'platform=macOS,arch=arm64' -derivedDataPath build
open build/Build/Products/Debug/Uzzy.app
```

Debug builds run as a separate app, «Uzzy Debug» (`com.akacronos.Uzzy.debug`), with an orange menu bar icon. They keep their own settings, so they can run next to the installed copy without touching it.

### Debug scenarios

Debug builds add a bar on top of the panel to pick a scenario: the real panel then shows one of its states («Desactualizado», «Sin sesión», «Respuesta incompatible»…) with fictional data, without touching the accounts. The scenarios drive the usage core through the same fakes as the tests. To open the panel straight on one, pass its id (see `app/UzzyCore/Scenarios.swift`):

```sh
build/Build/Products/Debug/Uzzy.app/Contents/MacOS/Uzzy -scenario stale
```

Release builds leave the scenarios, the fakes and the sample responses out.

### Repository layout

| Path | Contents |
|---|---|
| `app/` | The macOS app and its Xcode project, `Uzzy.xcodeproj`. |
| `app/Uzzy/` | App: menu bar icon, panel and SwiftUI presentation, plus the app icon (`AppIcon.icon`, an Icon Composer document). |
| `app/UzzyCore/` | Usage core: panel state, provider adapters and injectable dependencies. In Debug builds, also the fake dependencies, the sample responses and the debug scenarios. |
| `app/UzzyCoreTests/` | Tests through the usage core, with the fake dependencies. |
| `app/Config/` | Shared build settings (signing). |
| `brand/` | Vector masters of the logo, the app icon glyph and the menu bar icon, on a 32-unit grid. |
| `CONTEXT.md` | Domain vocabulary (used quota, reset, last valid reading…). |
| `docs/agents/` | Agent conventions: issues, triage labels, domain docs. |
| `docs/images/` | Screenshots used in this README. |
| `.agents/skills/` | Agent skills used to work on the repo, copied from their upstream repos (see `skills-lock.json`). |

Design decisions live in the [issues](https://github.com/aka-cronos/uzzy/issues?q=is%3Aissue) of map [#1](https://github.com/aka-cronos/uzzy/issues/1).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Disclaimer

The endpoints the app uses to read quotas are **internal and undocumented** by the providers. They may change or stop working without notice, and each person is responsible for using them within their provider's terms.

Uzzy is an independent project, not affiliated with, endorsed by or sponsored by the makers of Claude, Codex, ChatGPT or Cursor. All product names and trademarks belong to their respective owners.

## Acknowledgements

Endpoint research was informed by [OpenUsage](https://github.com/robinebers/openusage) (MIT) and [openai/codex](https://github.com/openai/codex) (Apache-2.0). No code was copied from either.

## License

[MIT](LICENSE). The agent skills under `.agents/skills/` are third-party MIT code; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
