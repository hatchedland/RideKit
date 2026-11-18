#!/usr/bin/env bash
# Runs the Kotlin RideKit's tests against the golden files in spec/fixtures.
# The first run downloads Gradle and the Kotlin/JUnit libraries (pinned in android/gradle/libs.versions.toml).
set -euo pipefail
cd "$(dirname "$0")/../android"

# Use a real JDK 21+ even if JAVA_HOME points somewhere stale (e.g. a removed Android Studio).
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
  JAVA_HOME=$(/usr/libexec/java_home -v 21+ 2>/dev/null || true)
  export JAVA_HOME
fi
exec ./gradlew :ridekit:test "$@"
