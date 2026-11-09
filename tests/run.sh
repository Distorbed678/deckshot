#!/usr/bin/env bash
# Runs the headless tests. A failure stops a release (see .github/workflows/release.yml).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
for suite in behaviour bots; do
  dir="$TMP/$suite"
  mkdir -p "$dir"
  cp "$ROOT/tests/$suite/"*.lua "$dir/"
  ln -s "$ROOT/data" "$dir/data"
  ln -s "$ROOT/assets" "$dir/assets"
  echo "== $suite"
  DECKSHOT_REPO="$ROOT" timeout 900 love "$dir" > "$TMP/$suite.log" 2>&1
  code=$?
  grep -E "^FAIL|ERROR on|^DONE|^END|rror:" "$TMP/$suite.log" | cut -c1-160
  [ "$code" -eq 0 ] || { echo "$suite failed (exit $code)"; fail=1; }
done
exit $fail
