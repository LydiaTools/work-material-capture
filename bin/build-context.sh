#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
/usr/bin/swiftc -O -parse-as-library -framework AppKit -framework ApplicationServices -framework ScreenCaptureKit "$root/Sources/ContextWatcher.swift" -o "$root/bin/context-watcher"
codesign --force --sign - "$root/bin/context-watcher" >/dev/null
