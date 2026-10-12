import AVKit
import Photos
import SwiftUI

/// A grid of photos/videos referenced from the Photos library.
struct MediaGrid: View {
    let links: [MediaLink]
    @Environment(RideRecorder.self) private var recorder
    @State private var selected: MediaLink?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 2)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(links) { link in
                Button { selected = link } label: {
                    AssetThumbnail(localIdentifier: link.localIdentifier, isVideo: link.isVideo)
                        .aspectRatio(1, contentMode: .fill)
                }
                .buttonStyle(.plain)
            }
        }
        .task { recorder.organizer.resolveLocalIdentifiers(links) }
        .fullScreenCover(item: $selected) { link in
            MediaViewer(links: links, initial: link)
        }
    }
}

/// Loads a small thumbnail through Photos' image cache.
struct AssetThumbnail: View {
    let localIdentifier: String
    let isVideo: Bool
    @State private var image: UIImage?
    @State private var missing = false

    var body: some View {
        Color.secondary.opacity(0.15)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if missing {
                    Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isVideo {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .padding(4)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            .clipped()
            .task(id: localIdentifier) {
                image = await PhotoImages.image(for: localIdentifier, size: CGSize(width: 240, height: 240))
                missing = image == nil
            }
    }
}

/// Full-screen swipe-through viewer. Videos play inline.
struct MediaViewer: View {
    let links: [MediaLink]
    let initial: MediaLink
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(links) { link in
                    Group {
                        if link.isVideo {
                            AssetVideo(localIdentifier: link.localIdentifier)
                        } else {
                            AssetFullImage(localIdentifier: link.localIdentifier)
                        }
                    }
                    .tag(Optional(link.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if let link = links.first(where: { $0.id == selection }) {
                        VStack {
                            Text(link.capturedAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.bold())
                            if let spot = link.spot { Text(spot.displayName).font(.caption) }
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear { selection = initial.id }
        }
    }
}

private struct AssetFullImage: View {
    let localIdentifier: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: localIdentifier) {
            image = await PhotoImages.image(for: localIdentifier, size: CGSize(width: 2_000, height: 2_000))
        }
    }
}

private struct AssetVideo: View {
    let localIdentifier: String
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: localIdentifier) {
            if let item = await PhotoImages.playerItem(for: localIdentifier) {
                player = AVPlayer(playerItem: item)
            }
        }
        .onDisappear { player?.pause() }
    }
}

/// Async wrappers around `PHImageManager`. Network access is allowed so iCloud-only items load.
enum PhotoImages {
    private static let manager = PHCachingImageManager()

    static func image(for localIdentifier: String, size: CGSize) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    static func playerItem(for localIdentifier: String) async -> AVPlayerItem? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { return nil }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        return await withCheckedContinuation { continuation in
            manager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }
}
