#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
OUTPUT="$PROJECT_ROOT/bin/capture-segment"
SOURCE="$PROJECT_ROOT/Sources/CaptureSegment.swift"

/usr/bin/swiftc -O -parse-as-library -framework AppKit -framework AVFoundation -framework ScreenCaptureKit "$SOURCE" -o "$OUTPUT"
codesign --force --sign - "$OUTPUT" >/dev/null
print -r -- "$OUTPUT"
