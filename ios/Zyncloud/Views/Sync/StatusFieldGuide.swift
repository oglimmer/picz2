import Foundation

/// Plain-English explanations for the readouts on the Status tab.
///
/// The numbers there are honest but not self-explanatory: "In scope" is not a to-do list,
/// "Last sync" is not when we last *looked*, and "Refresh" vs "Processing" is an iOS
/// distinction no user should have to know. Rather than pad every row with a caption — the
/// tab is a dense table on purpose — each section header carries an ⓘ that opens this.
///
/// Kept as pure data, away from the view, so the wording is testable and so a row added to
/// ``SyncLogView`` without a matching entry here fails a test rather than shipping unexplained.
struct StatusFieldGuide: Identifiable {
    struct Field: Identifiable {
        let name: String
        let text: String
        var id: String { name }
    }

    /// Matches the section header it was opened from; also the sheet's identity.
    let id: String
    let fields: [Field]

    var title: String { id }
}

extension StatusFieldGuide {
    /// - Parameters:
    ///   - syncLastDays: spelled into the "In scope" text, because "the last few days" is
    ///     exactly the vagueness that makes the number look wrong.
    ///   - includesSkippedTooLarge: the "Too big to back up" row only renders when it is
    ///     non-zero, so explaining it unconditionally would describe a row that is not there.
    static func current(syncLastDays: Int, includesSkippedTooLarge: Bool) -> StatusFieldGuide {
        var fields: [Field] = [
            Field(
                name: "Queued",
                text: "Photos waiting their turn to be sent. Only a few go at a time, so the phone stays usable and the battery lasts.",
            ),
            Field(
                name: "Uploading",
                text: "Photos being sent to the server right now.",
            ),
            Field(
                name: "Uploaded this session",
                text: "How many finished since the app last started. Closing and reopening the app sets it back to zero. It is not the total on the server.",
            ),
            Field(
                name: "In scope",
                text: "How many photos on this phone were taken in the last \(syncLastDays) \(syncLastDays == 1 ? "day" : "days"). This is not a to-do list — most of them are already backed up. Change the window under Options.",
            ),
            Field(
                name: "Last sync",
                text: "When a photo last finished uploading. If nothing needed sending, this does not move, even though the app did check.",
            ),
        ]

        if includesSkippedTooLarge {
            fields.append(Field(
                name: "Too big to back up",
                text: "Files the server refuses because of their size. They are skipped, not retried, so they are not backed up anywhere. Activity below names each one and its size. Raising the server's limit un-skips them by itself.",
            ))
        }

        return StatusFieldGuide(id: "Current", fields: fields)
    }

    /// iOS never promises background time; it decides. Every line here is written to make that
    /// the reader's takeaway, because the most common support question is "why is it not
    /// syncing" when the honest answer is "iOS has not given us a slot yet".
    static let backgroundTasks = StatusFieldGuide(
        id: "Background Tasks",
        fields: [
            Field(
                name: "Last scheduled",
                text: "When the app last asked iOS for time to sync in the background. It asks again every time you leave the app.",
            ),
            Field(
                name: "Refresh last run",
                text: "When iOS last gave the app a short slot — around 30 seconds. Enough to pick up a few new photos.",
            ),
            Field(
                name: "Processing last run",
                text: "When iOS last gave the app a long slot. These come less often, usually while charging on Wi‑Fi, and are where large batches actually get through.",
            ),
            Field(
                name: "Run count",
                text: "Short and long slots added together, since the app was installed. A number that never grows means iOS is not running the app in the background at all.",
            ),
        ],
    )
}
