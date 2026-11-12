#!/bin/sh
# Snaps installer. Builds from source, so macOS doesn't block it as a downloaded app.
#   Install / update: curl -fsSL https://raw.githubusercontent.com/amims71/snaps/main/install.sh | sh
#   Uninstall:        curl -fsSL https://raw.githubusercontent.com/amims71/snaps/main/install.sh | sh -s uninstall
set -e

SOURCE=${SNAPS_SOURCE:-https://github.com/amims71/snaps/archive/refs/heads/main.tar.gz}
APP=/Applications/Snaps.app
[ -w /Applications ] || APP="$HOME/Applications/Snaps.app"

if [ "$1" = uninstall ]; then
    for app in /Applications/Snaps.app "$HOME/Applications/Snaps.app"; do
        [ -d "$app" ] || continue
        "$app/Contents/MacOS/Snaps" --unregister || true   # removes the login item
        pkill -x Snaps || true
        rm -rf "$app"
    done
    defaults delete com.amims71.snaps >/dev/null 2>&1 || true
    tccutil reset All com.amims71.snaps >/dev/null 2>&1 || true
    echo "Snaps uninstalled."
    exit 0
fi

[ "$(uname)" = Darwin ] || { echo "Snaps runs on macOS only."; exit 1; }
if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]; then
    echo "Snaps needs macOS 14 (Sonoma) or later."; exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
    echo "Snaps is built on your Mac and needs Apple's Command Line Tools."
    xcode-select --install >/dev/null 2>&1 || true
    echo "Finish the install window that just opened, then run this command again."
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "Downloading Snaps…"
curl -fsSL "$SOURCE" | tar -xz -C "$WORK" --strip-components 1

echo "Building (takes about a minute the first time)…"
if ! "$WORK/build.sh" >"$WORK/build.log" 2>&1; then
    cat "$WORK/build.log"
    echo "Build failed. Please open an issue at https://github.com/amims71/snaps/issues with the output above."
    exit 1
fi

pkill -x Snaps || true
mkdir -p "$(dirname "$APP")"
rm -rf "$APP"
ditto "$WORK/build/Snaps.app" "$APP"
open "$APP"

cat <<'DONE'

Snaps is installed and running (pencil icon in the menu bar). It starts at login.

One-time setup: press ⇧⌘5, open Options, and choose "Save to: Clipboard".
Then every screenshot opens in Snaps. Draw, press ⌘C, and paste anywhere.
(Or keep your setup and use ⌃⇧⌘4, which always copies to the clipboard.)
DONE
