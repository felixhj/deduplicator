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

if [ -f "$bin/DedupCore.o" ]; then
    # Swift Build, SwiftPM's default from Swift 6.4: one object file per target.
    modules="$bin"
    modulemap="$(dirname "$(dirname "$bin")")/Intermediates.noindex/GeneratedModuleMaps/CTagLib.modulemap"
    objects="$bin/DedupCore.o $bin/DedupScanner.o $bin/CTagLib.o"
else
    # SwiftPM's older native build system, as in the Command Line Tools for Swift 6.3.
    modules="$bin/Modules"
    modulemap="$bin/CTagLib.build/module.modulemap"
    objects=$(find "$bin/DedupCore.build" "$bin/DedupScanner.build" "$bin/CTagLib.build" -name '*.o')
fi
sources=$(find App -name '*.swift')

# The object and source lists are meant to split into separate arguments.
# shellcheck disable=SC2086
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx15.0" \
    -sdk "$(xcrun --show-sdk-path)" \
    -I "$modules" \
    -Xcc -fmodule-map-file="$modulemap" \
    -Xcc -I -Xcc Sources/CTagLib/include \
    $sources $objects -lc++ -lz -o "$out"

echo "App sources compiled and linked: $out"
