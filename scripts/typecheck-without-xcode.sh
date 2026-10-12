#!/usr/bin/env bash
# Type-checks the app and widget sources against the macOS 26 SDK when full Xcode isn't installed.
#
# The Command Line Tools lack the iOS SDK and the SwiftData / Foundation macro plugins, so this
# works on a copy of the sources where:
#   - `@Model` is replaced by hand-written `PersistentModel` conformances (stubs)
#   - `#Predicate` is replaced by a function taking a typed closure, `@Query` by a property wrapper
#   - the few iOS-only ActivityKit / UIKit types the app uses get minimal macOS stand-ins, so one
#     unavailable type doesn't stop the compiler before it checks everything else. These stand-ins
#     only prove the code is self-consistent, not that it matches the real iOS signatures.
# The widget extension (ActivityConfiguration / DynamicIsland) is iOS-only and can't be checked this way;
# it's compiled as-is and its "unavailable in macOS" errors are expected.
# iOS-only APIs (UIKit, some SwiftUI modifiers, ActivityKit requests) are reported as
# "unavailable in macOS"; those are expected and listed separately.
#
# Once Xcode is installed, build the real thing instead:
#   xcodegen generate && xcodebuild -scheme RideTracker -destination 'generic/platform=iOS Simulator' build
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift build --package-path "$ROOT/Packages/RideKit" -c debug >/dev/null
MODULES="$ROOT/Packages/RideKit/.build/arm64-apple-macosx/debug/Modules"

mkdir -p "$WORK/app" "$WORK/widget"
cp -R "$ROOT/RideTracker/." "$WORK/app/"
cp "$ROOT"/Shared/*.swift "$WORK/app/"
cp "$ROOT"/RideTrackerWidgets/*.swift "$ROOT"/Shared/*.swift "$WORK/widget/"

python3 - "$WORK/app" "$WORK/widget" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
widget = pathlib.Path(sys.argv[2])
models = []
for f in root.rglob("*.swift"):
    s = f.read_text()
    for m in re.finditer(r"@Model\s+final class (\w+)", s):
        models.append(m.group(1))
    s = re.sub(r"@Model\s+", "", s)
    s = re.sub(r"@Attribute\([^)]*\)\s*", "", s)
    s = re.sub(r"@Relationship\([^)]*\)\s*", "", s)
    s = re.sub(r"#Predicate<(\w+)>\s*\{", r"__predicate(\1.self) {", s)
    s = s.replace("#Predicate {", "__predicate {")
    s = s.replace("@Query", "@__Query")
    f.write_text(s)

shim = ["import Foundation", "import Observation", "import SwiftData", "",
        "func __predicate<T>(_: T.Type = T.self, _ body: (T) -> Bool) -> Predicate<T> { fatalError() }",
        "@propertyWrapper struct __Query<Element: PersistentModel> {",
        "    var wrappedValue: [Element] { fatalError() }",
        "    init() {}",
        "    init<V: Comparable>(filter: Predicate<Element>? = nil, sort: KeyPath<Element, V>, order: SortOrder = .forward) {}",
        "}", ""]
for name in models:
    shim += [
        f"extension {name}: PersistentModel {{",
        f"    convenience init(backingData: any BackingData<{name}>) {{ fatalError() }}",
        f"    var persistentBackingData: any BackingData<{name}> {{ get {{ fatalError() }} set {{}} }}",
        "    static var schemaMetadata: [Schema.PropertyMetadata] { [] }",
        "}", ""]
(root / "__ModelShim.swift").write_text("\n".join(shim))

for f in root.rglob("*.swift"):
    s = f.read_text()
    if "import ActivityKit" in s:
        f.write_text(s.replace("import ActivityKit\n", ""))

shims = '''
import AppKit
import Foundation
import SwiftUI

// ActivityKit stand-ins (iOS-only framework)
protocol ActivityAttributes: Decodable, Encodable { associatedtype ContentState: Codable & Hashable }
struct ActivityContent<State> { init(state: State, staleDate: Date?) {} }
struct AlertConfiguration {
    struct AlertSound { static let `default` = AlertSound() }
    init(title: LocalizedStringResource, body: LocalizedStringResource, sound: AlertSound) {}
}
struct ActivityAuthorizationInfo { var areActivitiesEnabled: Bool { true } }
enum ActivityUIDismissalPolicy { case `default`, immediate }
struct PushType {}
final class Activity<A: ActivityAttributes> {
    static var activities: [Activity<A>] { [] }
    static func request(attributes: A, content: ActivityContent<A.ContentState>, pushType: PushType?) throws -> Activity<A> { fatalError() }
    func update(_ content: ActivityContent<A.ContentState>) async {}
    func update(_ content: ActivityContent<A.ContentState>, alertConfiguration: AlertConfiguration?) async {}
    func end(_ content: ActivityContent<A.ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy) async {}
}

// UIKit stand-ins
typealias UIImage = NSImage
extension Image { init(uiImage: UIImage) { self.init(nsImage: uiImage) } }
final class UIPasteboard { nonisolated(unsafe) static let general = UIPasteboard(); var url: URL?; var string: String? }
@MainActor final class UIApplication {
    static let shared = UIApplication()
    static let openSettingsURLString = "app-settings:"
    func canOpenURL(_ url: URL) -> Bool { true }
}
'''
(root / "__iOSShims.swift").write_text(shims)
PY

check() {
  local label=$1 dir=$2
  local out
  out=$(cd "$dir" && find . -name '*.swift' -print0 | xargs -0 xcrun swiftc -typecheck \
    -target arm64-apple-macos26.0 -swift-version 6 -continue-building-after-errors -I "$MODULES" 2>&1 || true)
  local errors
  errors=$(echo "$out" | grep -E "^[^ ].*: error:" | sed "s|^\./||" | sort -u || true)
  local platform real
  platform=$(echo "$errors" | grep -E "unavailable in macOS|cannot find (type )?'UI[A-Z][A-Za-z]*' in scope|has no member 'fullScreenCover'|has no member 'textInputAutocapitalization'|reference to member 'never'|DynamicIslandExpandedContentBuilder|generic parameter 'Expanded'|has no member 'page'|'(ActivityConfiguration|DynamicIsland[A-Za-z]*|ActivityViewContext)' is unavailable|cannot find '(ActivityConfiguration|DynamicIsland[A-Za-z]*)' in scope" || true)
  real=$(echo "$errors" | grep -vxF -f <(echo "$platform") | grep -v '^$' || true)
  echo "== $label =="
  echo "Real errors: $(echo -n "$real" | grep -c '' || true)"
  [ -n "$real" ] && echo "$real"
  echo "iOS-only API (expected on macOS): $(echo -n "$platform" | grep -c '' || true)"
  [ -n "${VERBOSE:-}" ] && [ -n "$platform" ] && echo "$platform"
  return 0
}

check "App" "$WORK/app"
check "Widget extension" "$WORK/widget"
