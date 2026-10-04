#!/usr/bin/env bash
# Downloads Uzzy.dmg from a release, draft or published, and checks what a
# script can: the signature, the notarization ticket, and the version and build
# inside it against the tagged commit. The browser download and the first
# launch stay with the maintainer.
set -euo pipefail

tag="${1:?usage: verify-dmg.sh <tag>}"
cd "$(git rev-parse --show-toplevel)"

project=app/Uzzy.xcodeproj/project.pbxproj
setting() {
  git show "$tag:$project" | sed -n "s/^[[:space:]]*$1 = \(.*\);$/\1/p" | sort -u
}
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }

work="$(mktemp -d)"
mount="$work/mount"
trap 'hdiutil detach "$mount" -quiet 2> /dev/null || true; rm -rf "$work"' EXIT

gh release download "$tag" --pattern Uzzy.dmg --dir "$work"
dmg="$work/Uzzy.dmg"

set -x
codesign --verify --strict "$dmg"
spctl --assess --type open --context context:primary-signature "$dmg"
xcrun stapler validate "$dmg"
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount" -quiet
# Not --strict: the Finder layout dmgbuild writes on the mounted copy fails it.
codesign --verify --deep "$mount/Uzzy.app"
spctl --assess --type exec "$mount/Uzzy.app"
xcrun stapler validate "$mount/Uzzy.app"
{ set +x; } 2> /dev/null

info="$mount/Uzzy.app/Contents/Info.plist"
got="$(plist "$info" CFBundleShortVersionString) ($(plist "$info" CFBundleVersion))"
want="$(setting MARKETING_VERSION) ($(setting CURRENT_PROJECT_VERSION))"
echo "Uzzy.dmg holds $got; $tag is $want"
[ "$got" = "$want" ]
echo "ok"
