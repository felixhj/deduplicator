#!/bin/sh
# Runs `swift test`, passing any arguments through.
#
# With only the Command Line Tools installed (no Xcode), SwiftPM doesn't pass
# Swift Testing's framework folder with -F, so `import Testing` fails. The
# generated test runner then also can't see Testing, and the framework's own
# rpath misses lib_TestingInterop.dylib. This adds the missing paths. With
# Xcode selected, or on Linux, it runs plain `swift test`.
set -eu

developer_dir="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
frameworks="$developer_dir/Library/Developer/Frameworks"

case "$developer_dir" in
*/CommandLineTools)
    if [ -d "$frameworks/Testing.framework" ]; then
        exec swift test \
            -Xswiftc -F -Xswiftc "$frameworks" \
            -Xlinker -rpath -Xlinker "$frameworks" \
            -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib" \
            "$@"
    fi
    ;;
esac

exec swift test "$@"
