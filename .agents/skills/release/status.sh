#!/usr/bin/env bash
# Prints where the release stands on origin/main, runs the checks a script can
# run, and names the stage the release skill should work on next. Read-only
# apart from `git fetch`. Exits 1 when a check fails.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
git fetch --quiet --tags origin main

project=app/Uzzy.xcodeproj/project.pbxproj

# setting <ref> <name>: the distinct values of a build setting across targets
setting() {
  git show "$1:$project" | sed -n "s/^[[:space:]]*$2 = \(.*\);$/\1/p" | sort -u
}

version="$(setting origin/main MARKETING_VERSION)"
build="$(setting origin/main CURRENT_PROJECT_VERSION)"
site="$(git show origin/main:site/src/content.ts \
  | sed -n 's/^export const VERSION = "\(.*\)";$/\1/p')"

releases="$(gh release list --limit 30 --json tagName,isDraft,isPrerelease,isLatest)"
latest="$(jq -r '.[] | select(.isLatest) | .tagName' <<<"$releases")"
drafts="$(jq -r '[.[] | select(.isDraft) | .tagName] | join(" ")' <<<"$releases")"
latest_build="$(setting "$latest" CURRENT_PROJECT_VERSION)"

# The tag this version is waiting on: the final one, else its newest candidate.
pending="$(git tag --list "v$version")"
if [ -z "$pending" ]; then
  pending="$(git tag --list "v$version-rc.*" --sort=-v:refname | head -n 1)"
fi
pending_release="$(jq -r --arg tag "$pending" \
  '.[] | select(.tagName == $tag) | if .isDraft then "draft" else "published" end' \
  <<<"$releases")"

app_commits="$(git log --oneline "$latest..origin/main" -- app)"
other_commits="$(git log --oneline "$latest..origin/main" \
  | grep -vxF -e "$app_commits" || true)"

echo "project    $(echo $version) (build $(echo $build))"
echo "published  $latest (build $(echo $latest_build))"
echo "site       $site"
echo "drafts     ${drafts:-none}"
echo "pending    ${pending:-none}${pending_release:+ ($pending_release)}"
echo
echo "Unreleased commits in app/:"
echo "${app_commits:-  none}"
echo
echo "Unreleased commits elsewhere (site/ is already live):"
echo "${other_commits:-  none}"
echo

failed=0
check() { # <description> <command...>
  local description="$1"
  shift
  if "$@"; then
    echo "ok    $description"
  else
    echo "FAIL  $description"
    failed=1
  fi
}

one_value() { [ "$(wc -l <<<"$1")" -eq 1 ] && [ -n "$1" ]; }
all_spanish() {
  local missing
  missing="$(git show origin/main:app/Uzzy/Localizable.xcstrings | jq -r '
    .strings | to_entries[]
    | select(.value.shouldTranslate != false)
    | select(.value.localizations.es == null
        or (.value.localizations.es.stringUnit != null
          and .value.localizations.es.stringUnit.state != "translated"))
    | "      " + .key')"
  [ -z "$missing" ] || { echo "$missing"; return 1; }
}
build_grew() { [ "$build" -gt "$latest_build" ]; }

check "every target has the same MARKETING_VERSION" one_value "$version"
check "every target has the same CURRENT_PROJECT_VERSION" one_value "$build"
check "every string has a Spanish translation" all_spanish
if [ "v$version" != "$latest" ]; then
  check "the build is above the published one" build_grew
fi
echo

if [ "v$version" = "$latest" ]; then
  if [ "$site" != "$version" ]; then
    stage=site
  elif [ -n "$app_commits" ]; then
    stage=bump
  else
    stage=idle
  fi
elif [ "$pending_release" = draft ]; then
  stage=draft
elif [ -n "$pending" ] && [ -z "$pending_release" ]; then
  stage=build
else
  stage=tag
fi
echo "stage: $stage"

exit "$failed"
