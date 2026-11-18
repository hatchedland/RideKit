import SwiftUI

/// Shown when the server says this build is too old to sync (`app_config.min_version`). Never during
/// a ride: RootView waits until the ride has ended. Nothing on the phone is lost; it syncs after the update.
struct UpdateRequiredView: View {
    let update: AccountService.UpdateRequired
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.down.app")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Brand.accent)
                .accessibilityHidden(true)
            Text("Update Ride Tracker")
                .font(.title2.weight(.bold))
            Text("This version can't sync with your account any more. Your rides and spots are safe on this phone and will sync once you update.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("You have \(AccountService.currentVersion) · needs \(update.minimum) or later")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if let url = update.storeURL {
                Button {
                    openURL(url)
                } label: {
                    Text("Update")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.highwayYellow)
                .foregroundStyle(Brand.asphalt)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.page.ignoresSafeArea())
    }
}
