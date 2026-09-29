#!/bin/sh
# Builds the app for release, for Apple silicon and Intel Macs, and zips it
# for a GitHub release: build/release/Deduplicator-<version>.zip.
#
# The app is signed to run locally, not signed with a Developer ID or
# notarised, so macOS asks before it first opens (see the README).
set -eu

cd "$(dirname "$0")/.."
version=$(awk -F'"' '/MARKETING_VERSION/ { print $2; exit }' project.yml)
out=build/release
rm -rf "$out"
mkdir -p "$out"

xcodegen generate >/dev/null
if ! xcodebuild -project Deduplicator.xcodeproj -scheme Deduplicator -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
    clean build >"$out/build.log" 2>&1; then
    tail -30 "$out/build.log"
    echo "The build failed; the whole log is in $out/build.log." >&2
    exit 1
fi

app="$out/Deduplicator.app"
ditto build/DerivedData/Build/Products/Release/Deduplicator.app "$app"
codesign --verify --deep --strict "$app"
echo "Built Deduplicator $version for $(lipo -archs "$app/Contents/MacOS/Deduplicator")."

# ditto keeps the signature and extended attributes intact, which zip doesn't.
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/Deduplicator-$version.zip"
echo "$out/Deduplicator-$version.zip"
