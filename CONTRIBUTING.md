# Contributing

Thanks for your interest in Uzzy. It is a small personal project, so please read this before you spend time on a change.

## Start with an issue

Open an [issue](https://github.com/aka-cronos/uzzy/issues/new/choose) before you open a pull request, and wait until it is agreed. Pull requests without an agreed issue may be closed. Design decisions live in the issues of map [#1](https://github.com/aka-cronos/uzzy/issues/1).

If a provider changed its API and a card now shows «Respuesta incompatible» or wrong data, use the **Provider API changed** template.

## Language

Write everything in English: issues, pull requests, commits, code, comments, tests and docs. The one exception is the app's user-facing copy, which is in English and Spanish in `app/Uzzy/Localizable.xcstrings`. Some older issues are in Spanish; they stay as they are.

## Build and test

You need macOS 27 on Apple Silicon and Xcode 27.

```sh
xcodebuild test -project app/Uzzy.xcodeproj -scheme Uzzy -destination 'platform=macOS,arch=arm64'
xcodebuild build -project app/Uzzy.xcodeproj -scheme Uzzy -destination 'platform=macOS,arch=arm64' -derivedDataPath build
open build/Build/Products/Debug/Uzzy.app
```

Debug builds run as a separate app, «Uzzy Debug» (`com.akacronos.Uzzy.debug`), with an orange menu bar icon. They keep their own settings, so they can run next to the installed copy without touching it.

Tests go through the usage core with the fake dependencies in `app/UzzyCore/Fakes.swift`; they never touch real sessions or the network. To see a panel state without touching your accounts, use the [debug scenarios](#debug-scenarios).

### Debug scenarios

Debug builds add a bar on top of the panel to pick a scenario: the real panel then shows one of its states («Desactualizado», «Sin sesión», «Respuesta incompatible»…) with fictional data, without touching the accounts. The scenarios drive the usage core through the same fakes as the tests. To open the panel straight on one, pass its id (see `app/UzzyCore/Scenarios.swift`):

```sh
build/Build/Products/Debug/Uzzy.app/Contents/MacOS/Uzzy -scenario stale
```

A Debug build never asks GitHub for the latest version. To see the panel's Update button, pass a version to offer:

```sh
build/Build/Products/Debug/Uzzy.app/Contents/MacOS/Uzzy -update 9.9.9
```

Release builds leave the scenarios, the fakes and the sample responses out.

### Install your own build

To keep your own build running day to day, build it in Release and copy it to `/Applications`. From the repo root you can paste the whole block; Terminal runs the three commands in order.

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

### Signing

No Apple Developer account is needed: by default the app is signed ad hoc ("Sign to Run Locally"). With ad hoc signing, macOS treats every rebuild as a different app, so the Keychain prompt to read Claude Code's session comes back after each build even if you chose «Always Allow».

To sign with your own team, create `app/Config/Local.xcconfig` (ignored by git):

```
DEVELOPMENT_TEAM = YOUR_TEAM_ID
CODE_SIGN_IDENTITY = Apple Development
```

Do not commit a team ID to `app/Uzzy.xcodeproj`.

If you created `Config/Local.xcconfig` before the app moved into `app/`, move it by hand to `app/Config/Local.xcconfig`; git does not track it, so it did not move with the rest:

```sh
mv Config/Local.xcconfig app/Config/Local.xcconfig
```

## Repository layout

| Path | Contents |
|---|---|
| `app/` | The macOS app and its Xcode project, `Uzzy.xcodeproj`. |
| `app/Uzzy/` | App: menu bar icon, panel and SwiftUI presentation, plus the app icon (`AppIcon.icon`, an Icon Composer document). |
| `app/UzzyCore/` | Usage core: panel state, provider adapters and injectable dependencies. In Debug builds, also the fake dependencies, the sample responses and the debug scenarios. |
| `app/UzzyCoreTests/` | Tests through the usage core, with the fake dependencies. |
| `app/Config/` | Shared build settings (signing). |
| `brand/` | Vector masters of the logo, the app icon glyph and the menu bar icon, on a 32-unit grid. |
| `GLOSSARY.md` | Domain vocabulary (used quota, reset, last valid reading…). |
| `docs/agents/` | Agent conventions: issues, triage labels, domain docs. |
| `docs/images/` | Screenshots used in the README, and `main-bg.jpg`, the background image. |
| `.agents/skills/` | `release`, the one agent skill that is this repo's own. The rest are the team's global skills, installed outside the repo. |

## Releases

Releases are built by [`.github/workflows/release.yml`](.github/workflows/release.yml) from a `v*` tag, never on a local Mac. It signs the app with Developer ID and Hardened Runtime, notarizes and staples both the app and `Uzzy.dmg`, and attaches `Uzzy.dmg` to a **draft** GitHub Release. Only the maintainer cuts releases. An agent can carry its share of the steps below with the `release` skill: it opens the pull requests, checks the draft's `Uzzy.dmg` and drafts the notes, and leaves the merges, the hand test and the publish to the maintainer.

1. **Bump.** Open a pull request that sets `MARKETING_VERSION` (e.g. `0.1.0`) and adds 1 to `CURRENT_PROJECT_VERSION` in every target of `app/Uzzy.xcodeproj`, and merge it.
2. **Tag.** Tag the merged commit on `main` and push the tag. The tag without its `v` and anything after a `-` must equal `MARKETING_VERSION`, or the workflow fails before it signs anything. Try the pipeline with a release candidate first; tags with a `-` become prereleases, which `releases/latest` ignores.

   ```sh
   git switch main && git pull
   git tag v0.1.0-rc.1
   git push origin v0.1.0-rc.1
   ```

3. **Try the draft.** When the workflow finishes, quit Uzzy, delete `/Applications/Uzzy.app`, then download `Uzzy.dmg` from the draft release in a browser and install it. It must open with the one-click "downloaded from the Internet" prompt, Finder's **Get Info** must show the new version and build, and every provider must still read. Your own account is enough: the browser quarantines every download, so Gatekeeper checks it again, and it tests the update path most users take. Use a macOS account that never ran Uzzy only when a release changes the first launch or the permissions it asks for.
4. **Publish.** Edit the notes if needed (they start from GitHub's generated notes, which also list site-only pull requests) and publish the draft. The site's download button points at `releases/latest/download/Uzzy.dmg`, so it only moves when a non-prerelease is published.
5. **Update the site.** Open a pull request that sets `VERSION` in `site/src/content.ts` to the published version, and merge it. It feeds the version line under the download button and the JSON-LD `softwareVersion`. Merge it only after publishing: every push to `main` that touches `site/` deploys uzzy.app, so an earlier merge would show a version `releases/latest` doesn't serve yet.

### Release secrets

The workflow runs in a `release` environment. In **Settings → Environments → New environment**, create `release`, and under **Deployment branches and tags** choose **Selected branches and tags** and add the tag rule `v*`. Then add these environment secrets:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | The Developer ID Application certificate with its private key, exported from Keychain Access as `.p12`, then `base64 -i DeveloperID.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting the `.p12` |
| `APP_STORE_CONNECT_API_KEY_P8` | The full contents of the `AuthKey_XXXXXXXXXX.p8` file, including the `BEGIN`/`END` lines |
| `APP_STORE_CONNECT_KEY_ID` | The key's ID |
| `APP_STORE_CONNECT_ISSUER_ID` | The issuer ID shown above the keys list |

The certificate comes from [Certificates](https://developer.apple.com/account/resources/certificates/list) → **+** → **Developer ID Application**. The API key comes from [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) → **Team Keys** → **+**, with the **Developer** role; Apple lets you download the `.p8` only once. The team ID is read from the certificate, so it is not a secret. If either leaks, revoke it in the same place and replace the secret.

### Tag ruleset

Only the maintainer may create `v*` tags. In **Settings → Rules → Rulesets → New ruleset → New tag ruleset**, name it `Release tags`, set **Enforcement status** to **Active**, add the target `v*` (**Include by pattern**), leave **Repository admin** in the bypass list, and turn on **Restrict creations**, **Restrict updates** and **Restrict deletions**.

## Data and privacy

Test fixtures and sample responses must be sanitized: no real tokens, emails, account IDs or provider responses, in code, issues or pull requests. See [Privacy](README.md#privacy) for what the app may read and where it may connect; a change that widens that needs to be agreed in an issue first.

## Domain language

Use the terms in [GLOSSARY.md](GLOSSARY.md) (subscription quota, reset, last valid reading, session, account…) in code, issues and pull requests.

## Commits and pull requests

- Never commit to `main`; every change reaches it through a pull request.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): summary`, imperative, lowercase, subject up to 72 characters. See the `commit-workflow` skill in [aka-cronos/skills](https://github.com/aka-cronos/skills).
- Keep one logical change per commit and link the issue in the pull request.

## Working with agents

The repository is developed with coding agents. [AGENTS.md](AGENTS.md) holds their instructions. The skills they use are the team's global ones, installed outside the repo; only `release`, which is specific to Uzzy, lives here, in `.agents/skills/` (linked from `.claude/skills/`). You don't need an agent to contribute, but the same rules apply to both.
