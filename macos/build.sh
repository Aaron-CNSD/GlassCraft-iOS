#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-artifacts/macos}"
mkdir -p "$out/GlassCraft.app/Contents/MacOS" "$out/GlassCraft.app/Contents/Resources"
for arch in arm64 x86_64; do
 swiftc -module-cache-path /private/tmp/glasscraft-module-cache -parse-as-library -O -target "$arch-apple-macosx13.0" macos/GlassCraft.swift -o "$out/GlassCraft-$arch"
done
lipo -create "$out/GlassCraft-arm64" "$out/GlassCraft-x86_64" -output "$out/GlassCraft.app/Contents/MacOS/GlassCraft"
cp macos/Info.plist "$out/GlassCraft.app/Contents/Info.plist"
codesign --force --deep --sign - "$out/GlassCraft.app"
ditto -c -k --sequesterRsrc --keepParent "$out/GlassCraft.app" "$out/GlassCraft-macOS-universal.zip"
