#!/usr/bin/env bash
# Checks every file in community/ loads. Runs on pull requests that touch that folder.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/tests/community/"*.lua "$TMP/"
for d in data assets community; do ln -s "$ROOT/$d" "$TMP/$d"; done
DECKSHOT_REPO="$ROOT" timeout 120 love "$TMP"
