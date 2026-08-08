#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
packet="$repo_root/docs/design/visit-edit-context"
chrome="/Users/rob/Library/Caches/ms-playwright/chromium_headless_shell-1234/chrome-headless-shell-mac-arm64/chrome-headless-shell"
render_profile_root="$(mktemp -d /private/tmp/visit-edit-context-render.XXXXXX)"
trap 'rm -rf "$render_profile_root"' EXIT

render() {
  local name="$1"
  "$chrome" \
    --headless \
    --disable-gpu \
    --hide-scrollbars \
    --force-device-scale-factor=1 \
    --disable-background-networking \
    --disable-component-update \
    --disable-sync \
    --no-first-run \
    --no-default-browser-check \
    --user-data-dir="$render_profile_root/$name" \
    --screenshot="$packet/visit-edit-context-$name.png" \
    --window-size=390,844 \
    "file://$packet/visit-edit-context-$name.html"
}

render default
render ax
