import Foundation
import Photos
import Testing
@testable import Zyncloud

/// The Permissions section is now conditional, so the four derived properties that decide what
/// it says — and whether it appears at all — are worth pinning.
///
/// The bug this guards against is a specific one: `.limited` used to read green and hide the
/// action button, which made "Photos only gave us the assets you hand-picked" look like
/// "everything is fine". A background sync in that state silently skips most of the library.
@MainActor
struct PhotoAccessPresentationTests {
    private func viewModel(_ status: PHAuthorizationStatus) -> SyncOptionsViewModel {
        let viewModel = SyncOptionsViewModel(apiClient: nil)
        viewModel.authStatus = status
        return viewModel
    }

    // MARK: - Visibility

    /// Full access is the steady state and the whole point of hiding the section.
    @Test func fullAccessHidesTheSection() {
        #expect(!viewModel(.authorized).showsPermissionsSection)
    }

    @Test(arguments: [
        PHAuthorizationStatus.limited,
        .denied,
        .restricted,
        .notDetermined,
    ])
    func everyOtherStateKeepsTheSectionVisible(status: PHAuthorizationStatus) {
        #expect(viewModel(status).showsPermissionsSection)
    }

    // MARK: - Colour

    @Test func onlyFullAccessIsGreen() {
        #expect(viewModel(.authorized).photoAccessColor == "green")
    }

    /// The regression itself: limited access must not read as "all good".
    @Test func limitedAccessIsNotGreen() {
        #expect(viewModel(.limited).photoAccessColor == "orange")
    }

    @Test(arguments: [PHAuthorizationStatus.denied, .restricted])
    func aBlockedStateIsRed(status: PHAuthorizationStatus) {
        #expect(viewModel(status).photoAccessColor == "red")
    }

    // MARK: - Hint

    /// The hidden state is the only one with nothing to say.
    @Test func fullAccessHasNoHint() {
        #expect(viewModel(.authorized).photoAccessHint == nil)
    }

    @Test(arguments: [
        PHAuthorizationStatus.limited,
        .denied,
        .restricted,
        .notDetermined,
    ])
    func everyVisibleStateExplainsItself(status: PHAuthorizationStatus) {
        let hint = viewModel(status).photoAccessHint
        #expect(hint != nil)
        #expect(!(hint ?? "").isEmpty)
    }

    // MARK: - Which button

    /// `requestAuthorization` only shows a system prompt from `.notDetermined`. From any other
    /// state it returns the same answer without presenting anything, so offering "Request
    /// Access" there is a button that does nothing.
    @Test func onlyNotDeterminedCanBePrompted() {
        #expect(viewModel(.notDetermined).canRequestAccess)
        #expect(!viewModel(.denied).canRequestAccess)
        #expect(!viewModel(.restricted).canRequestAccess)
        #expect(!viewModel(.limited).canRequestAccess)
        #expect(!viewModel(.authorized).canRequestAccess)
    }
}
