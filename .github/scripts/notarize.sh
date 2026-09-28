#!/bin/sh
# Submits a file to Apple's notary service with the App Store Connect API key
# and waits for the verdict. Fails, printing Apple's log, unless it is
# Accepted. Used by .github/workflows/release.yml.
#
# Needs API_KEY_PATH, APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID.

set -eu

file="$1"
result="$(mktemp)"
trap 'rm -f "$result"' EXIT

xcrun notarytool submit "$file" \
  --key "$API_KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait \
  --output-format json > "$result" || true

cat "$result"
echo

status="$(plutil -extract status raw -o - "$result" 2> /dev/null || echo "")"
if [ "$status" != "Accepted" ]; then
  id="$(plutil -extract id raw -o - "$result" 2> /dev/null || echo "")"
  if [ -n "$id" ]; then
    xcrun notarytool log "$id" \
      --key "$API_KEY_PATH" \
      --key-id "$APP_STORE_CONNECT_KEY_ID" \
      --issuer "$APP_STORE_CONNECT_ISSUER_ID" || true
  fi
  echo "::error::Notarization of $(basename "$file") ended with status '${status:-unknown}'."
  exit 1
fi
