#!/bin/sh
# Compiles and links the app's Swift sources against the package without
# Xcode, to catch compile and link errors on a Mac with only the Command Line
# Tools. The result is a bare executable, not an app bundle: build the real
# app with XcodeGen and Xcode.
set -eu
cd "$(dirname "$0")/.."

swift build
bin="$(swift build --show-bin-path)"
out="${TMPDIR:-/tmp}/DeduplicatorAppCheck"
objects=$(find "$bin/DedupCore.build" "$bin/DedupScanner.build" "$bin/CTagLib.build" -name '*.o')
sources=$(find App -name '*.swift')

# The object and source lists are meant to split into separate arguments.
# shellcheck disable=SC2086
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx15.0" \
    -sdk "$(xcrun --show-sdk-path)" \
    -I "$bin/Modules" \
    -Xcc -fmodule-map-file="$bin/CTagLib.build/module.modulemap" \
    -Xcc -I -Xcc Sources/CTagLib/include \
    $sources $objects -lc++ -lz -o "$out"

echo "App sources compiled and linked: $out"
