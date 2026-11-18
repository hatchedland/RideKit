#!/usr/bin/env bash
# Builds the Android app (debug APK by default). Extra arguments go to Gradle, e.g.
#   ./scripts/build-android.sh :app:installDebug      # onto a running emulator / USB phone
set -euo pipefail
cd "$(dirname "$0")/../android"

# Use a real JDK 21+ even if JAVA_HOME points somewhere stale (e.g. a removed Android Studio).
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
  JAVA_HOME=$(/usr/libexec/java_home -v 21+ 2>/dev/null || true)
  export JAVA_HOME
fi
if [ $# -eq 0 ]; then set -- :app:assembleDebug; fi
exec ./gradlew "$@"
