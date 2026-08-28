import Foundation
import Testing
@testable import Zyncloud

/// The Status tab's ⓘ sheets. Pinned because the wording *is* the feature here — a glossary
/// that has drifted from the rows it describes is worse than no glossary.
struct StatusFieldGuideTests {
    private func current(days: Int = 3, tooLarge: Bool = false) -> StatusFieldGuide {
        .current(syncLastDays: days, includesSkippedTooLarge: tooLarge)
    }

    // MARK: - Coverage

    /// One entry per row rendered in `SyncLogView`'s "Current" section, in the same order.
    /// A row added there without a line here shows a number with no explanation.
    @Test func theCurrentSectionExplainsEveryAlwaysVisibleRow() {
        #expect(current().fields.map(\.name) == [
            "Queued",
            "Uploading",
            "Uploaded this session",
            "In scope",
            "Last sync",
        ])
    }

    @Test func theBackgroundSectionExplainsEveryRow() {
        #expect(StatusFieldGuide.backgroundTasks.fields.map(\.name) == [
            "Last scheduled",
            "Refresh last run",
            "Processing last run",
            "Run count",
        ])
    }

    /// "Too big to back up" only renders when the count is non-zero, so explaining it
    /// unconditionally would describe a row that is not on screen.
    @Test func theSizeSkipRowIsExplainedOnlyWhenItIsShown() {
        #expect(!current(tooLarge: false).fields.contains { $0.name == "Too big to back up" })
        #expect(current(tooLarge: true).fields.contains { $0.name == "Too big to back up" })
    }

    @Test func noExplanationIsEmpty() {
        for guide in [current(tooLarge: true), .backgroundTasks] {
            for field in guide.fields {
                #expect(!field.text.isEmpty, "\(field.name) has no explanation")
            }
        }
    }

    // MARK: - The sync window

    /// "the last few days" is exactly the vagueness that makes the In-scope number look wrong,
    /// so the user's actual setting is spelled into the sentence.
    @Test(arguments: [2, 3, 30, 365])
    func theInScopeTextNamesTheUsersOwnWindow(days: Int) {
        let text = current(days: days).fields.first { $0.name == "In scope" }?.text ?? ""
        #expect(text.contains("last \(days) days"))
    }

    /// A one-day window must not read "last 1 days".
    @Test func aOneDayWindowIsSingular() {
        let text = current(days: 1).fields.first { $0.name == "In scope" }?.text ?? ""
        #expect(text.contains("last 1 day"))
        #expect(!text.contains("1 days"))
    }

    // MARK: - Sheet identity

    /// `sheet(item:)` keys off `id`, so the two guides must not collide — tapping one ⓘ and
    /// then the other has to swap the sheet's contents.
    @Test func theTwoGuidesHaveDistinctIdentities() {
        #expect(current().id != StatusFieldGuide.backgroundTasks.id)
    }

    /// The title over the sheet is the header the user tapped, so it reads as an answer to
    /// that section rather than a generic help page.
    @Test func theTitleMatchesTheSectionHeader() {
        #expect(current().title == "Current")
        #expect(StatusFieldGuide.backgroundTasks.title == "Background Tasks")
    }

    /// Each row's name is its identity in the sheet's `List`; duplicates would drop rows.
    @Test func fieldNamesAreUniqueWithinAGuide() {
        for guide in [current(tooLarge: true), .backgroundTasks] {
            #expect(Set(guide.fields.map(\.id)).count == guide.fields.count)
        }
    }
}
