#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
source_path="$repo_root/docs/design/design-system/w2-settings-about.html"
output_dir="$repo_root/docs/design/design-system"
browser_path=${MT_CHROMIUM_BIN:-}
expected_browser_version=151.0.7922.34

if [ -z "$browser_path" ]; then
    if [ -n "${PLAYWRIGHT_BROWSERS_PATH:-}" ]; then
        playwright_cache=$PLAYWRIGHT_BROWSERS_PATH
    elif [ "$(uname -s)" = Darwin ]; then
        playwright_cache="$HOME/Library/Caches/ms-playwright"
    else
        playwright_cache="$HOME/.cache/ms-playwright"
    fi

    for candidate in "$playwright_cache"/chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell; do
        if [ -x "$candidate" ] &&
            candidate_version=$("$candidate" --version 2>/dev/null) &&
            case "$candidate_version" in *"$expected_browser_version") true ;; *) false ;; esac
        then
            browser_path=$candidate
            break
        fi
    done
fi

if [ -z "$browser_path" ]; then
    echo "Set MT_CHROMIUM_BIN to a Chromium or Playwright headless-shell executable." >&2
    exit 1
fi

actual_browser_version=$("$browser_path" --version)
case "$actual_browser_version" in
    *"$expected_browser_version") ;;
    *)
        echo "W-2 renders require Chromium $expected_browser_version; found $actual_browser_version." >&2
        exit 1
        ;;
esac

render() {
    variant=$1
    output=$2

    # 900×900 is the evidence canvas around the HTML's ruled 390×844 frame.
    # Change the two sizes together only when the design-canvas ruling changes.
    "$browser_path" \
        --headless \
        --disable-gpu \
        --hide-scrollbars \
        --force-device-scale-factor=1 \
        --window-size=900,900 \
        --screenshot="$output_dir/$output" \
        "file://$source_path?variant=$variant"
}

render settings w2-settings.png
render settings-ax w2-settings-ax.png
render about w2-about.png
render about-ax w2-about-ax.png
