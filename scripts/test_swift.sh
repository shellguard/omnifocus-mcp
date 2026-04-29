#!/bin/sh
# test_swift.sh — run the Swift unit tests in Tests/OmniFocusCoreTests.
#
# When running under Command Line Tools (no Xcode) the Swift Testing
# framework's runtime path is not on the default dyld search list, so
# we have to inject -F / -rpath flags and DYLD env vars. Xcode users
# can ignore this script and run `swift test` directly.
set -eu

CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
CLT_LIBS="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

if [ ! -d "$CLT_FRAMEWORKS/Testing.framework" ]; then
  echo "warning: Testing.framework not found at $CLT_FRAMEWORKS — falling back to plain swift test" >&2
  exec swift test "$@"
fi

DYLD_FRAMEWORK_PATH="$CLT_FRAMEWORKS" \
DYLD_LIBRARY_PATH="$CLT_LIBS" \
exec swift test \
  -Xswiftc -F -Xswiftc "$CLT_FRAMEWORKS" \
  -Xlinker -F -Xlinker "$CLT_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$CLT_LIBS" \
  "$@"
