#!/bin/sh
# Renders background.html into background.png (640x400) and background@2x.png
# (1280x800), the Uzzy.dmg window background. Run it on a Mac with Google
# Chrome after changing background.html, brand/logo.svg or
# docs/images/main-bg.jpg, and commit both PNGs; the release workflow only
# combines them into a TIFF.

set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$here/../.."
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

# The logo's path, inlined so it can take currentColor. Rendered next to
# background.html so its relative link to the wallpaper still resolves.
page="$here/.background.rendered.html"
trap 'rm -f "$page"' EXIT
logo="$(sed -n 's/.*<path d="\([^"]*\)".*/\1/p' "$root/brand/logo.svg")"
sed "s|d=\"LOGO\"|d=\"$logo\"|" "$here/background.html" > "$page"

for scale in 1 2; do
  suffix=""
  [ "$scale" = 2 ] && suffix="@2x"
  "$chrome" --headless --disable-gpu --hide-scrollbars \
    --force-device-scale-factor="$scale" --window-size=640,400 \
    --screenshot="$here/background$suffix.png" "file://$page" 2> /dev/null
done

sips -g pixelWidth -g pixelHeight "$here/background.png" "$here/background@2x.png"
