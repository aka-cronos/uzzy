---
name: release
description: >-
  Release: use when a new version of Uzzy needs cutting, or a
  release already under way needs carrying on.
---

# Release

A release moves through **stages**, and each one ends on something only GitHub or the
maintainer can do: a merge, a workflow run, a hand test. So one run of this skill works one
stage, and the next run picks the release up where it stands.

"Releases" in [CONTRIBUTING.md](../../../CONTRIBUTING.md) is the source of truth for the
procedure and its reasons; read it before the first stage. This skill is the agent's share of it.

Three actions belong to the maintainer:

- **Merging** a release pull request. Open it, get it green, and ask.
- **Pushing a `v*` tag** is yours only after a go-ahead for that exact tag in this
  conversation: it signs and notarizes with the release secrets.
- **Trying the draft by hand and publishing it.**

## Step 1: Read the stage

Run `.agents/skills/release/status.sh`. It fetches `origin/main`, prints the versions, the
unreleased commits and the mechanical checks, and names the stage.

**Done when:** you know the stage and every check reads `ok`. A `FAIL` is fixed in its own pull
request before the release goes on; report it and stop there.

## Stage: bump

The published version is the project's version, and `app/` has unreleased commits.

1. **Pick the version.** A `feat` among the unreleased commits in `app/` makes it a minor; only
   fixes make it a patch. Propose it with the list of what ships and let the maintainer confirm.
2. **Audit the docs.** For every unreleased commit in `app/` that changes what a user sees, find
   the sentence in `README.md` and in `site/src/content.ts` that describes the new behaviour. A
   change in what the app reads, stores or connects to must also show in the README's "Privacy"
   and in the site's privacy copy. Route each gap:
   - `README.md` and other repo docs: a docs pull request, merged before the tag so the tag
     carries it.
   - Site copy: hold it for the site stage, because merging it deploys it. Note it in the bump
     pull request so the site stage finds it.

   Report the reverse too: site copy already live that describes behaviour the published
   version lacks.
3. **Open the bump pull request** from `release/<version>`: set `MARKETING_VERSION` and add 1 to
   `CURRENT_PROJECT_VERSION` in every target of `app/Uzzy.xcodeproj`, committed as
   `chore(app): bump version to <version> (build <n>)`. Versions quoted in `app/UzzyCoreTests`
   are fixtures; they stay as they are.

**Done when:** every user-visible change has its sentence or a routed gap, the pull request's
`Build and test` check is green, both settings hold one value each across all targets, and the
maintainer has been asked to merge.

## Stage: tag

The bump is on `main` and its version has no tag yet, or its release candidate passed.

1. **Choose the tag.** `v<version>` is the default. Start with `v<version>-rc.<n>` when
   `git diff --stat <published tag>..origin/main -- .github` shows the release pipeline changed
   since it last ran.
2. **Ask for the go-ahead**, showing the tag, the commit it lands on and the commits it ships.
3. **Tag `origin/main` and push the tag**, then follow the `Release` workflow run to its end
   with `gh run watch`.

A failed run: read the failed step's log. Rerun a transient failure (a notarization timeout)
with `gh run rerun --failed`. One that needs a code change goes back to the maintainer with the
log, since the fix lands through a pull request and they decide what happens to the tag.

**Done when:** the run succeeded and `status.sh` reads `stage: draft`.

The `build` stage is this one from the watch onward: the tag is pushed and its run has not
produced a release yet.

## Stage: draft

The workflow left a draft release with `Uzzy.dmg`.

1. **Verify the artifact.** Run `.agents/skills/release/verify-dmg.sh <tag>`: it checks the
   signature, the notarization ticket and Gatekeeper on the `.dmg` and the app inside, and that
   the app holds the tagged version and build. Check with `gh release view <tag>` that the asset
   is named exactly `Uzzy.dmg`, which the site's download link depends on, and that the release
   is a prerelease exactly when the tag has a `-`.
2. **Write the notes.** Replace GitHub's generated list with one sentence per change a user
   would notice, in the vocabulary of `CONTEXT.md`, each ending in its pull request number. Leave
   out site-only, docs, CI and chore pull requests; keep the "Full Changelog" line. Apply them
   with `gh release edit <tag> --notes-file`.
3. **Hand over.** Give the maintainer the draft's URL, the notes, "Try the draft" from
   CONTRIBUTING.md as their checklist, and one line per shipped change saying where to look for
   it in the installed app. Then stop: the hand test and the publish are theirs.

When the maintainer reports that a release candidate passed, go to the tag stage for the final
tag on the same commit.

**Done when:** `verify-dmg.sh` ends on `ok`, the notes are on the draft, and the maintainer has
the URL and the checklist.

## Stage: site

The version is published and the site still shows the previous one.

1. **Open the site pull request** from `chore/site-version-<version>`: set `VERSION` in
   `site/src/content.ts`, add the site copy held back in the bump stage, and commit it as
   `chore(site): show version <version>`. Ask the maintainer to merge.
2. **Check the deploy** once it is merged: `curl -s https://uzzy.app` carries the new
   `softwareVersion`, and `curl -sIL` on `DOWNLOAD_URL` from `site/src/content.ts` redirects
   through the new tag.

**Done when:** uzzy.app serves the new version and its download link resolves to the new tag.

## Stage: idle

Nothing in `app/` is unreleased and the site shows the published version. Say so; the commits
listed elsewhere are already live or ship with nothing.
