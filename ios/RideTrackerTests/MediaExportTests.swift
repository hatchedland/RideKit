import Photos
import Testing
@testable import RideTracker

@Suite("Media export")
struct MediaExportTests {
    @Test func photoPrefersEditedVersion() {
        #expect(MediaExport.preferredResourceType(among: [.photo, .fullSizePhoto, .adjustmentData], isVideo: false) == .fullSizePhoto)
        #expect(MediaExport.preferredResourceType(among: [.photo, .adjustmentData], isVideo: false) == .photo)
    }

    @Test func livePhotoSharesTheStillImage() {
        #expect(MediaExport.preferredResourceType(among: [.photo, .pairedVideo], isVideo: false) == .photo)
    }

    @Test func videoPrefersEditedVersion() {
        #expect(MediaExport.preferredResourceType(among: [.video, .fullSizeVideo], isVideo: true) == .fullSizeVideo)
        #expect(MediaExport.preferredResourceType(among: [.video], isVideo: true) == .video)
    }

    @Test func nothingShareable() {
        #expect(MediaExport.preferredResourceType(among: [.adjustmentData], isVideo: false) == nil)
        #expect(MediaExport.preferredResourceType(among: [.photo], isVideo: true) == nil)
    }

    @Test func fileNamesStayUnique() {
        var used = Set<String>()
        #expect(MediaExport.uniqueName("IMG_0001.HEIC", used: &used) == "IMG_0001.HEIC")
        #expect(MediaExport.uniqueName("img_0001.heic", used: &used) == "img_0001 2.heic")
        #expect(MediaExport.uniqueName("IMG_0001.HEIC", used: &used) == "IMG_0001 3.HEIC")
        #expect(MediaExport.uniqueName("", used: &used) == "Item")
    }
}
