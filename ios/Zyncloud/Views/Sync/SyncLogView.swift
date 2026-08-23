import SwiftUI

struct SyncLogView: View {
    @StateObject private var logger = SyncLogger.shared

    var body: some View {
        NavigationView {
            Group {
                if logger.logs.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No sync activity yet")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Sync logs will appear here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    List {
                        ForEach(logger.logs) { log in
                            SyncLogEntryRow(log: log)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Sync Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            logger.clearLogs()
                        } label: {
                            Label("Clear Log", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
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
}
