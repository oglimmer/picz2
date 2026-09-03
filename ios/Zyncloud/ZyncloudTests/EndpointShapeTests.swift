import Foundation
import Testing

@testable import Zyncloud

/// What the newer endpoints actually put on the wire.
///
/// Every one of these was written against a server that was in front of the author at the time
/// and then never checked again. A wrong path, a wrong verb or a mis-spelled body key fails at
/// runtime and only at runtime — and one of them, `deleteAccount`, deletes the account and
/// everything in it, which is not a thing to find out about by trying it.
///
/// Serialized because the stub intercepts `URLSession.shared`, which is process-wide.
@Suite(.serialized)
struct EndpointShapeTests {
    private var api: APIClient { APIClient.stubbed }

    // MARK: - Account deletion

    /// The irreversible one. Wrong verb on this path and the app would be *reading* the account
    /// while telling the user it deleted it; wrong path and it would delete something else.
    @Test func deleteAccountSendsADeleteToTheAccountEndpoint() async {
        let request = await StubServer.captureOne {
            _ = await awaiting { done in api.deleteAccount(completion: done) }
        }

        #expect(request?.method == "DELETE")
        #expect(request?.path == "/api/users/account")
        #expect(request?.headers["Authorization"] == APIClient.stubbedAuthHeader)
        #expect(request?.body.isEmpty == true)
    }

    /// It has to be authenticated. An unauthenticated delete would either fail or — far worse
    /// on a misconfigured server — delete the wrong account.
    @Test func deleteAccountWithoutCredentialsSendsNoAuthorizationHeader() async {
        let request = await StubServer.captureOne {
            _ = await awaiting { done in APIClient().deleteAccount(completion: done) }
        }

        #expect(request?.headers["Authorization"] == nil)
    }

    /// A refusal must surface as a failure, not be swallowed into "deleted" — the caller wipes
    /// local credentials on success.
    @Test func arefusedDeleteAccountIsAFailure() async {
        var result: Result<Void, Error>?
        _ = await StubServer.capture(status: 403, json: "{\"success\":false,\"message\":\"Not allowed\"}") {
            result = await awaiting { done in api.deleteAccount(completion: done) }
        }

        guard case let .failure(error) = result else {
            Issue.record("a 403 must not read as a successful delete")
            return
        }
        #expect((error as? AppError)?.errorDescription?.contains("Not allowed") == true)
    }

    @Test func asuccessfulDeleteAccountReportsSuccess() async {
        var result: Result<Void, Error>?
        _ = await StubServer.capture(status: 204, json: "") {
            result = await awaiting { done in api.deleteAccount(completion: done) }
        }

        #expect((try? result?.get()) != nil)
    }

    // MARK: - Tags on one file

    @Test func addTagPostsTheTagNameToTheFile() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"tags\":[\"beach\"]}") {
            _ = await awaiting { done in api.addTag(fileId: 31, tagName: "beach", completion: done) }
        }

        #expect(request?.method == "POST")
        #expect(request?.path == "/api/files/31/tags")
        #expect(request?.headers["Content-Type"] == "application/json")
        #expect(request?.json["tagName"] as? String == "beach")
    }

    /// The answer is the file's whole new tag list, which is what the caller writes back over
    /// the photo — so it has to be read out of the response, not assumed.
    @Test func addTagAnswersWithTheFilesWholeNewTagList() async {
        var result: Result<[String], Error>?
        _ = await StubServer.capture(json: "{\"success\":true,\"tags\":[\"beach\",\"2024\"]}") {
            result = await awaiting { done in api.addTag(fileId: 31, tagName: "beach", completion: done) }
        }

        #expect((try? result?.get()) == ["beach", "2024"])
    }

    /// Removal is a DELETE with the tag in the path, not in a body.
    @Test func removeTagDeletesTheTagNamedInThePath() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"tags\":[]}") {
            _ = await awaiting { done in api.removeTag(fileId: 31, tagName: "beach", completion: done) }
        }

        #expect(request?.method == "DELETE")
        #expect(request?.path == "/api/files/31/tags/beach")
        #expect(request?.body.isEmpty == true)
    }

    // MARK: - Caption on one file

    @Test func updateCaptionPutsTheTextAndReadsTheUpdatedPhotoBack() async {
        let photoJSON = """
        {"id":31,"originalName":"IMG_0001.HEIC","publicToken":"t","size":2048,
         "uploadedAt":"2024-06-01T10:00:00Z","tags":[],"albumId":7,
         "caption":"Sunrise over the fjord"}
        """

        var result: Result<Photo, Error>?
        let request = await StubServer.captureOne(json: photoJSON) {
            result = await awaiting { done in
                api.updateCaption(id: 31, caption: "Sunrise over the fjord", completion: done)
            }
        }

        #expect(request?.method == "PUT")
        #expect(request?.path == "/api/files/31/caption")
        #expect(request?.headers["Content-Type"] == "application/json")
        #expect(request?.json["caption"] as? String == "Sunrise over the fjord")
        // The answer is the photo, not an ack: the caller writes the caption back from it.
        #expect((try? result?.get())?.caption == "Sunrise over the fjord")
    }

    /// Clearing is the same call with an empty string — there is no separate delete endpoint.
    @Test func updateCaptionSendsAnEmptyStringToClearIt() async {
        let photoJSON = """
        {"id":31,"originalName":"IMG_0001.HEIC","publicToken":"t","size":2048,
         "uploadedAt":"2024-06-01T10:00:00Z","tags":[],"albumId":7}
        """

        var result: Result<Photo, Error>?
        let request = await StubServer.captureOne(json: photoJSON) {
            result = await awaiting { done in api.updateCaption(id: 31, caption: "", completion: done) }
        }

        #expect(request?.json["caption"] as? String == "")
        #expect((try? result?.get())?.caption == nil)
    }

    // MARK: - Tags on a whole album

    @Test func addTagToAllFilesPostsToTheAlbumsBulkEndpoint() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"updatedCount\":12}") {
            _ = await awaiting { done in
                api.addTagToAllFiles(albumId: 7, tagName: "beach", completion: done)
            }
        }

        #expect(request?.method == "POST")
        #expect(request?.path == "/api/albums/7/files/tags/beach")
    }

    /// Same path, opposite verb. If these two ever converged, "remove from all" would add to
    /// all — a silent, album-wide, wrong write.
    @Test func removeTagFromAllFilesUsesTheSamePathWithDelete() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"updatedCount\":12}") {
            _ = await awaiting { done in
                api.removeTagFromAllFiles(albumId: 7, tagName: "beach", completion: done)
            }
        }

        #expect(request?.method == "DELETE")
        #expect(request?.path == "/api/albums/7/files/tags/beach")
    }

    /// The count of files that actually changed is what the confirmation message quotes.
    @Test func abulkTagAnswersWithHowManyFilesChanged() async {
        var result: Result<Int, Error>?
        _ = await StubServer.capture(json: "{\"success\":true,\"updatedCount\":12}") {
            result = await awaiting { done in
                api.addTagToAllFiles(albumId: 7, tagName: "beach", completion: done)
            }
        }

        #expect((try? result?.get()) == 12)
    }

    // MARK: - Which tags an album allows

    @Test func fetchEnabledTagsGetsTheAlbumsList() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"tags\":[]}") {
            _ = await awaiting { done in api.fetchEnabledTags(albumId: 7, completion: done) }
        }

        #expect(request?.method == "GET")
        #expect(request?.path == "/api/albums/7/enabled-tags")
    }

    /// A whole-list write, not a toggle: the ids go up as an array under `tagIds`, and anything
    /// left out is switched off. Sending the wrong key silently switches every tag off.
    @Test func setEnabledTagsPutsTheWholeIdList() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"tags\":[]}") {
            _ = await awaiting { done in
                api.setEnabledTags(albumId: 7, tagIds: [3, 1, 4], completion: done)
            }
        }

        #expect(request?.method == "PUT")
        #expect(request?.path == "/api/albums/7/enabled-tags")
        #expect(request?.headers["Content-Type"] == "application/json")
        #expect(request?.json["tagIds"] as? [Int] == [3, 1, 4])
    }

    /// An empty list is a legitimate write — "this album accepts only the system tags" — and
    /// must not be turned into a missing key.
    @Test func setEnabledTagsCanSendAnEmptyList() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"tags\":[]}") {
            _ = await awaiting { done in api.setEnabledTags(albumId: 7, tagIds: [], completion: done) }
        }

        #expect(request?.json["tagIds"] as? [Int] == [])
    }

    // MARK: - Account-wide tags

    @Test func fetchTagsGetsTheAccountList() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"tags\":[]}") {
            _ = await awaiting { done in api.fetchTags(completion: done) }
        }

        #expect(request?.method == "GET")
        #expect(request?.path == "/api/tags")
    }

    @Test func createTagPostsTheName() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"tag\":null}") {
            _ = await awaiting { done in api.createTag(name: "beach", completion: done) }
        }

        #expect(request?.method == "POST")
        #expect(request?.path == "/api/tags")
        #expect(request?.json["tagName"] as? String == "beach")
    }

    /// Rename is a PUT on the tag's own id — the *new* name in the body, the id in the path.
    @Test func updateTagPutsTheNewNameOnTheIdsPath() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"tag\":null}") {
            _ = await awaiting { done in api.updateTag(id: 9, name: "seaside", completion: done) }
        }

        #expect(request?.method == "PUT")
        #expect(request?.path == "/api/tags/9")
        #expect(request?.json["tagName"] as? String == "seaside")
    }

    @Test func deleteTagDeletesTheIdsPath() async {
        let request = await StubServer.captureOne {
            _ = await awaiting { done in api.deleteTag(id: 9, completion: done) }
        }

        #expect(request?.method == "DELETE")
        #expect(request?.path == "/api/tags/9")
    }

    // MARK: - Narration languages

    @Test func fetchLanguageSettingsGetsTheSettingsEndpoint() async {
        let request = await StubServer.captureOne(
            json: "{\"success\":true,\"language1\":\"German\",\"language2\":null}",
        ) {
            _ = await awaiting { done in api.fetchLanguageSettings(completion: done) }
        }

        #expect(request?.method == "GET")
        #expect(request?.path == "/api/settings/languages")
    }

    @Test func languageSettingsDecodeWithOneSlotUnset() async {
        var result: Result<LanguageSettingsResponse, Error>?
        _ = await StubServer.capture(json: "{\"success\":true,\"language1\":\"German\",\"language2\":null}") {
            result = await awaiting { done in api.fetchLanguageSettings(completion: done) }
        }

        let settings = try? result?.get()
        #expect(settings?.language1 == "German")
        #expect(settings?.language2 == nil)
    }

    /// The slot is part of the path and the name goes up under `value` — the server has one
    /// endpoint per slot rather than one payload carrying both.
    @Test(arguments: [1, 2])
    func setLanguageNamePutsTheNameOnTheSlotsPath(slot: Int) async {
        let request = await StubServer.captureOne {
            _ = await awaiting { done in
                api.setLanguageName(slot: slot, name: "German", completion: done)
            }
        }

        #expect(request?.method == "PUT")
        #expect(request?.path == "/api/settings/languages/\(slot)")
        #expect(request?.headers["Content-Type"] == "application/json")
        #expect(request?.json["value"] as? String == "German")
    }

    // MARK: - New photo visibility (D70)

    @Test func fetchNewAssetTagGetsTheSettingsEndpoint() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"tagName\":\"all\"}") {
            _ = await awaiting { done in api.fetchNewAssetTag(completion: done) }
        }

        #expect(request?.method == "GET")
        #expect(request?.path == "/api/settings/new-asset-tag")
    }

    @Test func newAssetTagDecodesToTheEnum() async {
        var result: Result<NewAssetTag, Error>?
        _ = await StubServer.capture(json: "{\"success\":true,\"tagName\":\"all\"}") {
            result = await awaiting { done in api.fetchNewAssetTag(completion: done) }
        }

        #expect((try? result?.get()) == .all)
    }

    /// An unset or unrecognised value must read as `.hidden`. The screen shows the answer as a
    /// promise about who can see the next photo, and the safe half of that promise is the one to
    /// make when the server said something we do not understand.
    @Test(arguments: ["null", "\"\"", "\"something-else\""])
    func unknownNewAssetTagFallsBackToHidden(raw: String) async {
        var result: Result<NewAssetTag, Error>?
        _ = await StubServer.capture(json: "{\"success\":true,\"tagName\":\(raw)}") {
            result = await awaiting { done in api.fetchNewAssetTag(completion: done) }
        }

        #expect((try? result?.get()) == .hidden)
    }

    /// `confirmed` always rides along: the server rejects an unconfirmed switch to `all`, and the
    /// caller has already put the warning in front of the user.
    @Test(arguments: [NewAssetTag.hidden, NewAssetTag.all])
    func setNewAssetTagPutsTheNameAndTheConfirmation(tag: NewAssetTag) async {
        let request = await StubServer.captureOne {
            _ = await awaiting { done in api.setNewAssetTag(tag, completion: done) }
        }

        #expect(request?.method == "PUT")
        #expect(request?.path == "/api/settings/new-asset-tag")
        #expect(request?.json["tagName"] as? String == tag.rawValue)
        #expect(request?.json["confirmed"] as? Bool == true)
    }

    // MARK: - Pausing phone uploads

    /// Pausing is a `DELETE` of the target album, the same request the web app's "Pause uploads"
    /// sends. A `PUT` of some placeholder album id instead would keep uploading, into the wrong
    /// album, while the screen said "Paused".
    @Test func pausingUploadsDeletesTheTargetAlbum() async {
        let request = await StubServer.captureOne {
            _ = await awaiting { done in api.clearTargetAlbum(completion: done) }
        }

        #expect(request?.method == "DELETE")
        #expect(request?.path == "/api/settings/target-album")
        #expect(request?.body.isEmpty == true)
    }

    /// A refused pause must read as a failure: the caller puts the picker back on the old album
    /// on one, and swallowing it would leave the screen claiming a pause the server never made.
    @Test func arefusedPauseIsAfailure() async {
        var result: Result<Void, Error>?
        _ = await StubServer.capture(status: 500, json: "{\"success\":false,\"message\":\"Nope\"}") {
            result = await awaiting { done in api.clearTargetAlbum(completion: done) }
        }

        guard case let .failure(error) = result else {
            Issue.record("a 500 must not read as a successful pause")
            return
        }
        #expect(error.localizedDescription.contains("Nope"))
    }

    // MARK: - Recordings

    @Test func fetchRecordingsGetsTheAlbumsRecordings() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"recordings\":[]}") {
            _ = await awaiting { done in api.fetchRecordings(albumId: 7, completion: done) }
        }

        #expect(request?.method == "GET")
        #expect(request?.path == "/api/albums/7/recordings")
    }

    @Test func deleteRecordingDeletesTheIdsPath() async {
        let request = await StubServer.captureOne {
            _ = await awaiting { done in api.deleteRecording(id: 42, completion: done) }
        }

        #expect(request?.method == "DELETE")
        #expect(request?.path == "/api/recordings/42")
    }

    /// The audio-status probe goes through the public-token route, which is unauthenticated on
    /// purpose — a share link has to be able to poll it too.
    @Test func recordingAudioStatusUsesThePublicTokenRoute() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"ready\":true}") {
            _ = await awaitingValue { done in
                api.fetchRecordingAudioStatus(publicToken: "tok_abc", completion: done)
            }
        }

        #expect(request?.method == "GET")
        #expect(request?.path == "/api/r/tok_abc/audio/status")
        #expect(request?.headers["Authorization"] == nil, "the public-token route takes no credentials")
    }

    /// The readiness of the stubbed answer, for the four-state tests below.
    ///
    /// `RecordingAudioStatus` on the server is three Java primitives, so all three keys are
    /// always on the wire — the fixtures here mirror that.
    private func readiness(status: Int = 200, json: String) async -> RecordingAudioReadiness {
        var answer: RecordingAudioReadiness = .unreachable
        _ = await StubServer.capture(status: status, json: json) {
            answer = await awaitingValue { done in
                api.fetchRecordingAudioStatus(publicToken: "tok_abc", completion: done)
            }
        }
        return answer
    }

    /// This endpoint folds failure into its answer rather than returning a `Result`, so the four
    /// states are the whole contract. A poll that reads "not ready" for a rendition that has
    /// failed spins for ever; one that reads "ready" too early hands `AVPlayer` a file that is
    /// not there yet.
    @Test func recordingAudioStatusMapsTheServersAnswerToTheFourStates() async {
        #expect(await readiness(json: "{\"success\":true,\"ready\":true,\"failed\":false}") == .ready)
        #expect(await readiness(json: "{\"success\":true,\"ready\":false,\"failed\":false}") == .notReady)
        #expect(await readiness(json: "{\"success\":true,\"ready\":false,\"failed\":true}") == .failed)
        #expect(await readiness(status: 500, json: "{}") == .unreachable)
        #expect(await readiness(json: "not json") == .unreachable)
    }

    /// `ready` wins over `failed`. A rendition that failed once and was then made anyway is
    /// playable, and refusing to play it would be wrong.
    @Test func recordingAudioIsReadyEvenIfAnEarlierAttemptFailed() async {
        #expect(await readiness(json: "{\"success\":true,\"ready\":true,\"failed\":true}") == .ready)
    }

    /// Documents a fragility rather than endorsing it: all three keys on
    /// `RecordingAudioStatusResponse` are non-optional, so a server that stopped sending one of
    /// them would make every poll read as `.unreachable` — the app would give up on a rendition
    /// that is sitting there ready.
    ///
    /// Safe today because the server's `RecordingAudioStatus` holds Java `boolean` primitives,
    /// which Jackson always writes. If that ever becomes a `Boolean`, this test fails first and
    /// the fix is to default the field client-side.
    @Test(arguments: [
        "{\"ready\":true,\"failed\":false}",
        "{\"success\":true,\"failed\":false}",
        "{\"success\":true,\"ready\":true}",
    ])
    func amissingKeyMakesTheWholePollUnreachable(json: String) async {
        #expect(await readiness(json: json) == .unreachable)
    }

    // MARK: - Presentation groups

    @Test func fetchPresentationGroupsGetsTheAlbumsGroups() async {
        let request = await StubServer.captureOne(json: "{\"success\":true,\"count\":0,\"groups\":[]}") {
            _ = await awaiting { done in api.fetchPresentationGroups(albumId: 7, completion: done) }
        }

        #expect(request?.method == "GET")
        #expect(request?.path == "/api/albums/7/presentation-groups")
        #expect(request?.headers["Authorization"] == APIClient.stubbedAuthHeader)
    }

    /// The four fields the shelving actually needs, spelled exactly as the server spells them.
    /// `text` is the one that does not match its column (`body_text`), so it is the one a rename
    /// would silently drop — a chapter would keep its heading and lose its paragraph.
    @Test func agroupDecodesItsTagAnchorLabelAndText() async {
        let json = """
        {"success":true,"count":1,"groups":[
          {"id":10,"albumId":7,"tag":"beach","startFileId":31,"label":"Morning",
           "text":"Before the rain.","createdAt":"2026-05-04T12:00:00Z","updatedAt":null}
        ]}
        """
        var result: Result<[PresentationGroup], Error>?
        _ = await StubServer.capture(json: json) {
            result = await awaiting { done in api.fetchPresentationGroups(albumId: 7, completion: done) }
        }

        let group = (try? result?.get())?.first
        #expect(group?.id == 10)
        #expect(group?.tag == "beach")
        #expect(group?.startFileId == 31)
        #expect(group?.label == "Morning")
        #expect(group?.text == "Before the rain.")
    }

    /// `body_text` is nullable, so most groups arrive with a null here. Decoding has to survive
    /// it — a throw would take every other chapter in the album down with it.
    @Test func agroupWithNoTextStillDecodes() async {
        let json = """
        {"success":true,"count":1,"groups":[
          {"id":11,"albumId":7,"tag":"beach","startFileId":32,"label":"Evening","text":null}
        ]}
        """
        var result: Result<[PresentationGroup], Error>?
        _ = await StubServer.capture(json: json) {
            result = await awaiting { done in api.fetchPresentationGroups(albumId: 7, completion: done) }
        }

        #expect((try? result?.get())?.first?.text == nil)
        #expect((try? result?.get())?.first?.label == "Evening")
    }

    // MARK: - Writing presentation groups

    private var groupJSON: String {
        """
        {"success":true,"group":{"id":10,"albumId":7,"tag":"beach","startFileId":31,
         "label":"Morning","text":"Before the rain."}}
        """
    }

    /// Create carries the two things a chapter is anchored by — the tag and the photo it starts
    /// at — alongside the words. Neither can be changed later, so getting them onto the wire here
    /// is the whole of it.
    @Test func creatingAgroupPostsTheTagAnchorAndWords() async {
        let draft = PresentationGroupDraft(label: "Morning", text: "Before the rain.")

        let request = await StubServer.captureOne(json: groupJSON) {
            _ = await awaiting { done in
                api.createPresentationGroup(
                    albumId: 7,
                    tag: "beach",
                    startFileId: 31,
                    draft: draft,
                    completion: done,
                )
            }
        }

        #expect(request?.method == "POST")
        #expect(request?.path == "/api/albums/7/presentation-groups")
        #expect(request?.json["tag"] as? String == "beach")
        #expect(request?.json["startFileId"] as? Int == 31)
        #expect(request?.json["label"] as? String == "Morning")
        #expect(request?.json["text"] as? String == "Before the rain.")
    }

    /// The stored group is what the caller keeps: the server trims the label and collapses a
    /// blank body to null, so echoing the draft back would leave the screen showing something
    /// slightly different from what was saved.
    @Test func creatingAgroupReturnsTheStoredGroup() async {
        var result: Result<PresentationGroup, Error>?
        _ = await StubServer.capture(json: groupJSON) {
            result = await awaiting { done in
                api.createPresentationGroup(
                    albumId: 7,
                    tag: "beach",
                    startFileId: 31,
                    draft: PresentationGroupDraft(label: "  Morning  ", text: nil),
                    completion: done,
                )
            }
        }

        #expect((try? result?.get())?.id == 10)
        #expect((try? result?.get())?.label == "Morning")
    }

    /// A chapter never changes tag or anchor — the server ignores both on update, and sending
    /// them would suggest otherwise to the next person reading this client.
    @Test func updatingAgroupSendsOnlyTheWords() async {
        let request = await StubServer.captureOne(json: groupJSON) {
            _ = await awaiting { done in
                api.updatePresentationGroup(
                    id: 10,
                    draft: PresentationGroupDraft(label: "Morning", text: "Before the rain."),
                    completion: done,
                )
            }
        }

        #expect(request?.method == "PUT")
        #expect(request?.path == "/api/presentation-groups/10")
        #expect(request?.json["label"] as? String == "Morning")
        #expect(request?.json["tag"] == nil)
        #expect(request?.json["startFileId"] == nil)
    }

    /// A cleared body has to reach the server as an absent key, not as an empty string — that is
    /// what makes `normalizedText` store null and the heading lose its paragraph.
    @Test func agroupWithNoTextSendsNoTextKey() async {
        let request = await StubServer.captureOne(json: groupJSON) {
            _ = await awaiting { done in
                api.updatePresentationGroup(
                    id: 10,
                    draft: PresentationGroupDraft(label: "Morning", text: nil),
                    completion: done,
                )
            }
        }

        #expect(request?.json["label"] as? String == "Morning")
        #expect(request?.json["text"] == nil)
    }

    @Test func deletingAgroupDeletesTheIdsPath() async {
        let request = await StubServer.captureOne {
            _ = await awaiting { done in api.deletePresentationGroup(id: 10, completion: done) }
        }

        #expect(request?.method == "DELETE")
        #expect(request?.path == "/api/presentation-groups/10")
    }

    /// A refused save must surface as a failure: the form stays open on one, and swallowing it
    /// would close the form over a chapter that was never stored.
    @Test func arefusedGroupSaveIsAfailure() async {
        var result: Result<PresentationGroup, Error>?
        _ = await StubServer.capture(status: 400, json: "{\"success\":false,\"message\":\"Label is required\"}") {
            result = await awaiting { done in
                api.updatePresentationGroup(
                    id: 10,
                    draft: PresentationGroupDraft(label: "Morning", text: nil),
                    completion: done,
                )
            }
        }

        guard case let .failure(error) = result else {
            Issue.record("a 400 must not read as a saved chapter")
            return
        }
        #expect(error.localizedDescription.contains("Label is required"))
    }

    // MARK: - The album's publish gate

    /// Publishing is a query parameter on a PUT with no body, matching the analytics-pause switch
    /// it sits beside on the server.
    @Test func publishingAnAlbumPutsTheFlagInTheQuery() async {
        let json = #"{"success":true,"album":{"id":7,"name":"Trip","published":true}}"#

        let request = await StubServer.captureOne(json: json) {
            _ = await awaiting { done in api.setAlbumPublished(albumId: 7, published: true, completion: done) }
        }

        #expect(request?.method == "PUT")
        #expect(request?.path == "/api/albums/7/published")
        #expect(request?.query["published"] == "true")
    }

    @Test func unpublishingSendsFalse() async {
        let json = #"{"success":true,"album":{"id":7,"name":"Trip","published":false}}"#

        let request = await StubServer.captureOne(json: json) {
            _ = await awaiting { done in api.setAlbumPublished(albumId: 7, published: false, completion: done) }
        }

        #expect(request?.query["published"] == "false")
    }

    /// A server too old to know about publishing omits the key. Reading that as "private" would
    /// hide the share link on every album the account owns, so absent means public.
    @Test func anAlbumWithoutTheFlagCountsAsPublished() throws {
        let json = Data(#"{"id":7,"name":"Trip"}"#.utf8)
        let album = try JSONDecoder().decode(Album.self, from: json)

        #expect(album.published == nil)
        #expect(album.isPublished)
    }

    @Test func anExplicitlyUnpublishedAlbumIsNotPublished() throws {
        let json = Data(#"{"id":7,"name":"Trip","published":false}"#.utf8)
        let album = try JSONDecoder().decode(Album.self, from: json)

        #expect(!album.isPublished)
    }

    // MARK: - The album's saved map view

    @Test func savingAmapViewPutsTheFourDegreesToTheAlbum() async {
        let json = """
        {"success":true,"album":{"id":7,"name":"Trip",
         "mapCenterLat":50.1,"mapCenterLng":8.6,"mapSpanLat":0.05,"mapSpanLng":0.08}}
        """
        let view = SavedMapView(centerLat: 50.1, centerLng: 8.6, spanLat: 0.05, spanLng: 0.08)

        let request = await StubServer.captureOne(json: json) {
            _ = await awaiting { done in api.setMapView(albumId: 7, view: view, completion: done) }
        }

        #expect(request?.method == "PUT")
        #expect(request?.path == "/api/albums/7/map-view")
        #expect(request?.json["centerLat"] as? Double == 50.1)
        #expect(request?.json["centerLng"] as? Double == 8.6)
        #expect(request?.json["spanLat"] as? Double == 0.05)
        #expect(request?.json["spanLng"] as? Double == 0.08)
    }

    /// The answer carries the album back, and it is the album that is believed — the server
    /// clamps an over-wide span, so echoing what was sent would leave the map disagreeing with
    /// what was stored.
    @Test func thesavedViewIsReadBackOffTheAnswer() async {
        let json = """
        {"success":true,"album":{"id":7,"name":"Trip",
         "mapCenterLat":50.1,"mapCenterLng":8.6,"mapSpanLat":180.0,"mapSpanLng":360.0}}
        """
        var result: Result<Album, Error>?
        _ = await StubServer.capture(json: json) {
            result = await awaiting { done in
                api.setMapView(
                    albumId: 7,
                    view: SavedMapView(centerLat: 50.1, centerLng: 8.6, spanLat: 999, spanLng: 999),
                    completion: done,
                )
            }
        }

        #expect((try? result?.get())?.savedMapView?.spanLat == 180.0)
        #expect((try? result?.get())?.savedMapView?.spanLng == 360.0)
    }

    /// Clearing is a DELETE on the same path, and the album comes back with the four fields null
    /// — which has to read as "no saved view", not as a decode failure.
    @Test func clearingAmapViewDeletesThePathAndLeavesNoView() async {
        let json = """
        {"success":true,"album":{"id":7,"name":"Trip","mapCenterLat":null,"mapCenterLng":null,
         "mapSpanLat":null,"mapSpanLng":null}}
        """
        var result: Result<Album, Error>?
        let request = await StubServer.captureOne(json: json) {
            result = await awaiting { done in api.clearMapView(albumId: 7, completion: done) }
        }

        #expect(request?.method == "DELETE")
        #expect(request?.path == "/api/albums/7/map-view")
        #expect((try? result?.get())?.savedMapView == nil)
    }

    /// An album payload from a server that predates the map fields must still decode — they are
    /// simply absent, not null.
    @Test func analbumPayloadWithNoMapFieldsStillDecodes() async {
        var result: Result<Album, Error>?
        _ = await StubServer.capture(json: "{\"success\":true,\"album\":{\"id\":7,\"name\":\"Trip\"}}") {
            result = await awaiting { done in api.clearMapView(albumId: 7, completion: done) }
        }

        #expect((try? result?.get())?.id == 7)
        #expect((try? result?.get())?.savedMapView == nil)
    }

    // MARK: - Errors reach the caller

    /// Every one of these endpoints funnels through the same error ladder. Spot-check that the
    /// server's own words survive the trip rather than being replaced by a generic message.
    @Test func aserverErrorMessageReachesTheCaller() async {
        var result: Result<[String], Error>?
        _ = await StubServer.capture(status: 400, json: "{\"success\":false,\"message\":\"Tag not enabled for this album\"}") {
            result = await awaiting { done in api.addTag(fileId: 31, tagName: "beach", completion: done) }
        }

        guard case let .failure(error) = result else {
            Issue.record("a 400 must not read as success")
            return
        }
        #expect(error.localizedDescription.contains("Tag not enabled for this album"))
    }

    /// A body that does not match the model is a failure, not an empty success — an "applied"
    /// message over a change that never happened is the worst outcome.
    @Test func anunreadableBodyIsAFailureRatherThanAnEmptyResult() async {
        var result: Result<Int, Error>?
        _ = await StubServer.capture(json: "{\"success\":true}") {
            result = await awaiting { done in
                api.addTagToAllFiles(albumId: 7, tagName: "beach", completion: done)
            }
        }

        #expect((try? result?.get()) == nil)
    }
}
