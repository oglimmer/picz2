import SwiftUI

/// The "Log" tab: what sync is doing right now, when iOS last gave us background time,
/// and the running history — read top to bottom as one story.
///
/// Status and background-task counters used to sit on the Sync tab, next to the switches
/// that change behaviour. They are readouts, not settings, so they live here with the log
/// they explain; the Sync tab is now only things you can change.
struct SyncLogView: View {
    @EnvironmentObject private var sync: SyncCoordinator
    @StateObject private var logger = SyncLogger.shared
    @ObservedObject private var taskLog = BackgroundTaskLog.shared
    /// Only read for the sync window, which the "In scope" explanation spells out.
    @ObservedObject private var settings = Settings.shared

    /// The open explanation sheet, if any. One `@State` for both sections: they can never be
    /// open at once, and `sheet(item:)` re-presents correctly when the identity changes.
    @State private var guide: StatusFieldGuide?

    /// "Never" is a real answer here, and the most important one to read at a glance — so it is
    /// spelled out rather than shown as an empty value.
    private static func stamp(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }

    var body: some View {
        NavigationStack {
            List {
                // Sync status. §3.3 was undetectable in code and would have been obvious here:
                // background tasks were only ever scheduled at launch, and the only symptom was
                // sync quietly stopping. Scheduled and run are shown separately because "iOS has
                // not granted us time yet" and "we never asked" are different faults.
                Section(
                    header: sectionHeader("Current") {
                        guide = .current(
                            syncLastDays: settings.syncLastDays,
                            includesSkippedTooLarge: sync.metrics.skippedTooLarge > 0,
                        )
                    },
                    footer: sync.metrics.skippedTooLarge > 0
                        ? Text("Some files are larger than this server accepts, so they were not backed up. The entries below name them and their size.")
                        : Text(""),
                ) {
                    LabeledContent("Queued", value: "\(sync.metrics.queued)")
                    LabeledContent("Uploading", value: "\(sync.metrics.uploading)")
                    LabeledContent("Uploaded this session", value: "\(sync.metrics.uploaded)")
                    LabeledContent("In scope", value: "\(sync.metrics.inScope)")
                    LabeledContent("Last sync", value: Self.stamp(sync.metrics.lastSync))
                    // Only shown when it is non-zero: a permanent "Too big: 0" row would train
                    // the eye to skip the one line that means part of the library is unprotected.
                    if sync.metrics.skippedTooLarge > 0 {
                        LabeledContent("Too big to back up",
                                       value: "\(sync.metrics.skippedTooLarge)")
                            .foregroundColor(.orange)
                    }
                }

                Section(
                    header: sectionHeader("Background Tasks") { guide = .backgroundTasks },
                    footer: Text(taskLog.hasScheduledButNeverRun
                        ? "Scheduled, but iOS has not granted background time yet. This is normal for a while after install; if it persists for days, scheduling is broken."
                        : "iOS decides when these run. Long gaps are normal; \"never\" is not."),
                ) {
                    LabeledContent("Last scheduled", value: Self.stamp(taskLog.lastScheduled))
                    LabeledContent("Refresh last run",
                                   value: Self.stamp(taskLog.lastRun(.refresh)))
                    LabeledContent("Processing last run",
                                   value: Self.stamp(taskLog.lastRun(.processing)))
                    LabeledContent("Run count",
                                   value: "\(taskLog.runCount(.refresh) + taskLog.runCount(.processing))")
                }

                // The history itself. The empty state is a row inside the section rather than a
                // full-screen placeholder, because the status sections above are always worth
                // showing — even before the first sync has ever run.
                Section(header: Text("Activity")) {
                    if logger.logs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No sync activity yet")
                                .foregroundColor(.secondary)
                            Text("Sync logs will appear here")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(logger.logs) { log in
                            SyncLogEntryRow(log: log)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .sheet(item: $guide) { StatusFieldGuideSheet(guide: $0) }
            .navigationTitle("Sync Status")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            logger.clearLogs()
                        } label: {
                            Label("Clear Log", systemImage: "trash")
                        }
                        .disabled(logger.logs.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    /// A section header with an ⓘ on the trailing edge. The rows below it are a dense table of
    /// counters, and captioning each one would roughly double the height of both sections —
    /// so the explanation is one tap away instead of always on screen.
    private func sectionHeader(_ title: String, showGuide: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: showGuide) {
                Image(systemName: "info.circle")
                    .imageScale(.large)
            }
            // Without this the whole header behaves like one tappable row in a List.
            .buttonStyle(.borderless)
            .accessibilityLabel("What the \(title) values mean")
        }
    }
}

/// The explanation itself: one field per row, name over meaning.
struct StatusFieldGuideSheet: View {
    let guide: StatusFieldGuide
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(guide.fields) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.name)
                        .font(.headline)
                    Text(field.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .navigationTitle(guide.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Medium first: the sheet is a glossary you glance at, not a page you read.
        .presentationDetents([.medium, .large])
    }
}

struct SyncLogEntryRow: View {
    let log: SyncLogEntry

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: log.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundColor(log.success ? .green : .red)

            // Message and timestamp
            VStack(alignment: .leading, spacing: 4) {
                Text(log.message)
                    .font(.body)
                    .lineLimit(2)

                Text(formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Execution type badge
            HStack(spacing: 4) {
                Image(systemName: log.isManual ? "hand.tap.fill" : "clock.fill")
                    .font(.caption2)
                Text(log.isManual ? "Manual" : "Background")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(log.isManual ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
            .foregroundColor(log.isManual ? .green : .blue)
            .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: log.timestamp)
    }
}

#Preview {
    SyncLogView()
        .environmentObject(SyncCoordinator.shared)
}
