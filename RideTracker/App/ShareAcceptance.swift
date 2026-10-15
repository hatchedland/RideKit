import CloudKit
import UIKit

/// Receives friend invitations. iOS hands an accepted CloudKit share to the scene delegate, both
/// when the app is running and when the link launches it, so SwiftUI gets a small UIKit delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            ShareAcceptance.receive(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        ShareAcceptance.receive(cloudKitShareMetadata)
    }
}

/// Holds an invitation until the app's `FriendsService` is ready to accept it.
@MainActor
enum ShareAcceptance {
    private static var pending: [CKShare.Metadata] = []
    private static var handler: ((CKShare.Metadata) -> Void)?

    static func receive(_ metadata: CKShare.Metadata) {
        if let handler { handler(metadata) } else { pending.append(metadata) }
    }

    static func install(_ handler: @escaping (CKShare.Metadata) -> Void) {
        self.handler = handler
        pending.forEach(handler)
        pending = []
    }
}
