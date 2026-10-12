import Foundation
import Photos
import RideKit

/// Everything that touches the Photos library: permission, the "Ride Tracker" folder, one album
/// per ride, filling albums by capture time, and turning `PHAsset`s into `MediaCandidate`s.
///
/// Albums are always filled from the ride's **time window**, not only from live change events, so
/// a photo is never missed even if the app was suspended or killed while it was taken.
final class PhotoLibraryService: NSObject, @unchecked Sendable {
    static let folderTitle = "Ride Tracker"
    private static let folderIDKey = "photos.folderLocalIdentifier"

    private let library = PHPhotoLibrary.shared()
    private let observerLock = NSLock()
    private var onLibraryChange: (@Sendable () -> Void)?

    // MARK: Permission

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Full access is needed to see photos taken by any camera app during the ride.
    var hasFullAccess: Bool { authorizationStatus == .authorized }

    @discardableResult
    func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    // MARK: Albums

    /// Creates the ride's album inside the "Ride Tracker" folder and returns its identifier.
    func createAlbum(named title: String) async throws -> String {
        let folder = try await rideTrackerFolder()
        var albumID: String?
        try await library.performChanges {
            let create = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            let placeholder = create.placeholderForCreatedAssetCollection
            albumID = placeholder.localIdentifier
            PHCollectionListChangeRequest(for: folder)?.addChildCollections([placeholder] as NSArray)
        }
        guard let albumID else { throw CocoaError(.fileWriteUnknown) }
        return albumID
    }

    func renameAlbum(_ albumID: String, to title: String) async throws {
        guard let album = album(albumID) else { return }
        try await library.performChanges {
            PHAssetCollectionChangeRequest(for: album)?.title = title
        }
    }

    /// Deletes the album only; the photos stay in the library. iOS asks the user to confirm.
    func deleteAlbum(_ albumID: String) async throws {
        guard let album = album(albumID) else { return }
        try await library.performChanges {
            PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray)
        }
    }

    /// Adds every item in `window` that isn't in the album yet. Returns the new items.
    @discardableResult
    func sweep(albumID: String, window: RideMediaWindow) async throws -> [MediaCandidate] {
        guard hasFullAccess, let album = album(albumID) else { return [] }
        let candidates = self.candidates(in: window)
        let existing = assetIDs(in: album)
        let toAdd = window.itemsToAdd(from: candidates, alreadyInAlbum: existing)
        guard !toAdd.isEmpty else { return [] }

        try await addToAlbum(albumID, assetIDs: toAdd)
        let added = Set(toAdd)
        return candidates.filter { added.contains($0.id) }
    }

    func addToAlbum(_ albumID: String, assetIDs: [String]) async throws {
        guard let album = album(albumID), !assetIDs.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        try await library.performChanges {
            PHAssetCollectionChangeRequest(for: album)?.addAssets(assets)
        }
    }

    func albumItemCount(_ albumID: String) -> Int {
        guard let album = album(albumID) else { return 0 }
        return PHAsset.fetchAssets(in: album, options: nil).count
    }

    // MARK: Candidates

    /// Library items captured inside `window` (screenshots filtered later by the window's rules).
    func candidates(in window: RideMediaWindow) -> [MediaCandidate] {
        candidates(from: window.start, to: window.end)
    }

    func candidates(from start: Date, to end: Date) -> [MediaCandidate] {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND (mediaType == %d OR mediaType == %d)",
            start as NSDate, end as NSDate,
            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeHiddenAssets = false

        var result: [MediaCandidate] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            result.append(MediaCandidate(asset))
        }
        return result
    }

    func candidates(forIdentifiers ids: [String]) -> [MediaCandidate] {
        var result: [MediaCandidate] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            result.append(MediaCandidate(asset))
        }
        return result
    }

    // MARK: Cross-device identifiers

    func cloudIdentifiers(for localIDs: [String]) -> [String: String] {
        guard !localIDs.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for (localID, mapping) in library.cloudIdentifierMappings(forLocalIdentifiers: localIDs) {
            if case .success(let cloudID) = mapping { result[localID] = cloudID.stringValue }
        }
        return result
    }

    /// Maps cloud identifiers (from another device) to this device's local identifiers.
    func localIdentifiers(forCloud cloudIDs: [String]) -> [String: String] {
        guard !cloudIDs.isEmpty else { return [:] }
        let ids = cloudIDs.map { PHCloudIdentifier(stringValue: $0) }
        var result: [String: String] = [:]
        for (cloudID, mapping) in library.localIdentifierMappings(for: ids) {
            if case .success(let localID) = mapping { result[cloudID.stringValue] = localID }
        }
        return result
    }

    func asset(_ localID: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil).firstObject
    }

    // MARK: Live changes

    /// Calls `handler` (on a background queue) whenever the library changes, e.g. a photo is taken.
    func observeChanges(_ handler: @escaping @Sendable () -> Void) {
        observerLock.withLock {
            if onLibraryChange == nil { library.register(self) }
            onLibraryChange = handler
        }
    }

    func stopObserving() {
        observerLock.withLock {
            if onLibraryChange != nil { library.unregisterChangeObserver(self) }
            onLibraryChange = nil
        }
    }

    // MARK: Private

    private func album(_ id: String) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    private func assetIDs(in album: PHAssetCollection) -> Set<String> {
        var ids = Set<String>()
        PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
        return ids
    }

    /// The "Ride Tracker" folder, created on first use. Found again by title if the stored ID is stale.
    private func rideTrackerFolder() async throws -> PHCollectionList {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: Self.folderIDKey),
           let folder = PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [id], options: nil).firstObject {
            return folder
        }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "localizedTitle == %@", Self.folderTitle)
        if let existing = PHCollectionList.fetchCollectionLists(with: .folder, subtype: .regularFolder, options: options).firstObject {
            defaults.set(existing.localIdentifier, forKey: Self.folderIDKey)
            return existing
        }

        var folderID: String?
        try await library.performChanges {
            folderID = PHCollectionListChangeRequest
                .creationRequestForCollectionList(withTitle: Self.folderTitle)
                .placeholderForCreatedCollectionList.localIdentifier
        }
        guard let folderID,
              let folder = PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [folderID], options: nil).firstObject
        else { throw CocoaError(.fileWriteUnknown) }
        defaults.set(folderID, forKey: Self.folderIDKey)
        return folder
    }
}

extension PhotoLibraryService: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        let handler = observerLock.withLock { onLibraryChange }
        handler?()
    }
}

extension MediaCandidate {
    init(_ asset: PHAsset) {
        let kind: Kind
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            kind = .screenshot
        } else if asset.mediaSubtypes.contains(.videoScreenRecording) {
            kind = .screenRecording
        } else if asset.mediaType == .video {
            kind = .video
        } else if asset.mediaSubtypes.contains(.photoLive) {
            kind = .livePhoto
        } else {
            kind = .photo
        }
        self.init(
            id: asset.localIdentifier,
            capturedAt: asset.creationDate ?? .distantPast,
            coordinate: asset.location.map { Coordinate($0.coordinate) },
            kind: kind
        )
    }
}
