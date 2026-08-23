import Foundation
import Photos
import Testing
@testable import Zyncloud

/// The export switch used to read "not a video means JPEG", which made every iPhone HEIC photo
/// describe itself as `image/jpeg`. These cases pin the two halves that matters: the resource's
/// own type identifier wins, and the old hardcoded values remain the answer when there isn't one.
struct ExportFormatTests {
    // MARK: - The type identifier wins

    /// The case the change exists for. An unedited iPhone photo is HEIC, and the server has a
    /// whole HEIC→JPEG branch that `image/jpeg` routes straight past.
    @Test func aHeicPhotoIsNotCalledAJpeg() {
        let format = ExportFormat.forResource(type: .photo, uniformTypeIdentifier: "public.heic")
        #expect(format.mimeType == "image/heic")
        #expect(format.fileExtension == "heic")
    }

    @Test func aJpegPhotoIsStillAJpeg() {
        let format = ExportFormat.forResource(type: .photo, uniformTypeIdentifier: "public.jpeg")
        #expect(format.mimeType == "image/jpeg")
    }

    @Test func aPngPhotoKeepsItsOwnType() {
        let format = ExportFormat.forResource(type: .photo, uniformTypeIdentifier: "public.png")
        #expect(format.mimeType == "image/png")
        #expect(format.fileExtension == "png")
    }

    @Test func anMp4IsNotRenamedToQuicktime() {
        let format = ExportFormat.forResource(type: .video, uniformTypeIdentifier: "public.mpeg-4")
        #expect(format.mimeType == "video/mp4")
        #expect(format.fileExtension == "mp4")
    }

    @Test func aQuicktimeMovieKeepsMov() {
        let format = ExportFormat.forResource(
            type: .fullSizeVideo,
            uniformTypeIdentifier: "com.apple.quicktime-movie",
        )
        #expect(format.mimeType == "video/quicktime")
        #expect(format.fileExtension == "mov")
    }

    // MARK: - Falling back

    /// No identifier at all: behave exactly as the old switch did, so a resource that cannot
    /// describe itself is no worse off than before.
    @Test func aPhotoWithNoTypeIdentifierFallsBackToJpeg() {
        let format = ExportFormat.forResource(type: .photo, uniformTypeIdentifier: nil)
        #expect(format == ExportFormat.photoFallback)
    }

    @Test func aVideoWithNoTypeIdentifierFallsBackToQuicktime() {
        let format = ExportFormat.forResource(type: .video, uniformTypeIdentifier: nil)
        #expect(format == ExportFormat.videoFallback)
    }

    /// An identifier the system does not know about resolves to nothing usable, which has to
    /// land on the fallback rather than producing an empty extension.
    @Test func anUnknownTypeIdentifierFallsBack() {
        let format = ExportFormat.forResource(
            type: .photo,
            uniformTypeIdentifier: "com.example.not.a.real.type",
        )
        #expect(format == ExportFormat.photoFallback)
    }

    /// The movie half of a Live Photo. Classing it with photos would name an MOV `.jpg` on the
    /// fallback path — the exact shape of the bug being fixed.
    @Test func thePairedVideoOfALivePhotoFallsBackToVideo() {
        let format = ExportFormat.forResource(type: .pairedVideo, uniformTypeIdentifier: nil)
        #expect(format == ExportFormat.videoFallback)
    }

    @Test func anUnrecognisedResourceKindIsTreatedAsAPhoto() {
        let format = ExportFormat.forResource(type: .adjustmentData, uniformTypeIdentifier: nil)
        #expect(format == ExportFormat.photoFallback)
    }
}
