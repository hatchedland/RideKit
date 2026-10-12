#!/usr/bin/env bash
# Runs the RideKit unit tests.
# With full Xcode installed, plain `swift test` works. With only the Command Line Tools,
# Swift Testing lives outside the default search path, so we point the compiler at it. Its
# Foundation overlay ships without module files there, so cross-import overlays are turned off.
set -euo pipefail
cd "$(dirname "$0")/../Packages/RideKit"

CLT_FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if xcode-select -p | grep -q CommandLineTools && [ -d "$CLT_FRAMEWORKS" ]; then
  exec swift test \
    -Xswiftc -F"$CLT_FRAMEWORKS" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -F"$CLT_FRAMEWORKS" -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS" "$@"
fi
exec swift test "$@"
