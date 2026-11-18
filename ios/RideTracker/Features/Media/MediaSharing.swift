import Photos
import SwiftUI
import UIKit

/// Exports Photos library items as original files so they can go to the share sheet
/// (WhatsApp, Instagram, Messages, AirDrop, Save to Files, …).
enum MediaExport {
    enum ExportError: LocalizedError {
        case missing
        case noResource

        var errorDescription: String? {
            switch self {
            case .missing: "This item is no longer in your Photos library."
            case .noResource: "This item couldn't be read from Photos."
            }
        }
    }

    /// The resource to share: the edited version when there is one, otherwise the original.
    /// For Live Photos the still image is shared, which every app accepts.
    static func preferredResourceType(among available: [PHAssetResourceType], isVideo: Bool) -> PHAssetResourceType? {
        let order: [PHAssetResourceType] = isVideo
            ? [.fullSizeVideo, .video]
            : [.fullSizePhoto, .photo, .alternatePhoto]
        return order.first { available.contains($0) }
    }

    /// Writes each item's original file into a fresh temporary folder and returns the file URLs,
    /// in the same order. Items that only exist in iCloud are downloaded first.
    static func files(for localIdentifiers: [String]) async throws -> (folder: URL, files: [URL]) {
        let folder = URL.temporaryDirectory.appending(path: "Share-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var byID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }

        var urls: [URL] = []
        var usedNames = Set<String>()
        for id in localIdentifiers {
            guard let asset = byID[id] else { throw ExportError.missing }
            let resources = PHAssetResource.assetResources(for: asset)
            guard let type = preferredResourceType(among: resources.map(\.type), isVideo: asset.mediaType == .video),
                  let resource = resources.first(where: { $0.type == type })
            else { throw ExportError.noResource }

            let url = folder.appending(path: uniqueName(resource.originalFilename, used: &usedNames))
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
            urls.append(url)
        }
        return (folder, urls)
    }

    /// Photos often has several "IMG_0001.HEIC" across devices; keep every shared file name distinct.
    static func uniqueName(_ name: String, used: inout Set<String>) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = name.isEmpty ? "Item" : name
        var counter = 2
        while used.contains(candidate.lowercased()) {
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            counter += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }
}

/// Opens the Photos app. iOS has no public way to open Photos at a specific item, so this
/// opens the app itself; ride albums are under Albums › Ride Tracker.
enum PhotosApp {
    static let url = URL(string: "photos-redirect://")!
}

/// A request to share one or more Photos items.
struct MediaShareRequest: Identifiable, Equatable {
    let id = UUID()
    let localIdentifiers: [String]
}

extension View {
    /// Prepares the requested items and presents the system share sheet.
    func mediaSharing(_ request: Binding<MediaShareRequest?>) -> some View {
        modifier(MediaSharingModifier(request: request))
    }
}

private struct MediaSharingModifier: ViewModifier {
    @Binding var request: MediaShareRequest?

    private struct Prepared: Identifiable {
        let id = UUID()
        let folder: URL
        let files: [URL]
    }

    @State private var preparing = false
    @State private var prepared: Prepared?
    /// Kept apart from `prepared`, which SwiftUI clears before `onDismiss` runs.
    @State private var folderToClean: URL?
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .overlay {
                if preparing {
                    ProgressView("Preparing \(request?.localIdentifiers.count ?? 1) item(s)…")
                        .padding(20)
                        .background(.regularMaterial, in: .rect(cornerRadius: 14))
                }
            }
            .task(id: request?.id) {
                guard let request else { return }
                preparing = true
                defer {
                    preparing = false
                    self.request = nil
                }
                do {
                    let result = try await MediaExport.files(for: request.localIdentifiers)
                    folderToClean = result.folder
                    prepared = Prepared(folder: result.folder, files: result.files)
                } catch {
                    self.error = error.localizedDescription
                }
            }
            .sheet(item: $prepared, onDismiss: cleanUp) { prepared in
                ActivityView(items: prepared.files)
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
            .alert("Couldn't share", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
    }

    private func cleanUp() {
        // Share targets copy what they need while the sheet is open; the temporary files can go.
        if let folderToClean {
            try? FileManager.default.removeItem(at: folderToClean)
        }
        folderToClean = nil
    }
}

/// `UIActivityViewController` for file URLs, which every share target understands.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
