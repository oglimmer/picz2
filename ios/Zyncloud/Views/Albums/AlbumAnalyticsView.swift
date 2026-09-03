import SwiftUI

/// What visitors did with a shared album — the phone's read of the web app's analytics page.
///
/// Opened from the album menu as a sheet, so it carries its own Done button. Everything on it
/// is owner-only, and none of it is collected by this app: a browser hitting the share link is
/// what makes these numbers move.
struct AlbumAnalyticsView: View {
    let album: Album

    @StateObject private var viewModel: AlbumAnalyticsViewModel
    @Environment(\.dismiss) private var dismiss

    init(album: Album) {
        self.album = album
        _viewModel = StateObject(wrappedValue: AlbumAnalyticsViewModel(albumId: album.id))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let stats = viewModel.stats {
                    figures(stats)
                } else if let loadError = viewModel.loadError {
                    ContentUnavailableView {
                        Label("No analytics", systemImage: "chart.bar.xaxis")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try Again") { viewModel.load() }
                    }
                } else {
                    ProgressView("Loading analytics…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.load()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel("Refresh")
                }
            }
            .alert(state: $viewModel.alertState)
            .onAppear {
                if viewModel.stats == nil {
                    viewModel.load()
                }
            }
        }
    }

    // MARK: - The figures

    private func figures(_ stats: AlbumAnalytics) -> some View {
        List {
            Section {
                countingRow
            } footer: {
                Text(viewModel.isCounting
                    ? "Visits to \"\(album.name)\" through its share link are being counted."
                    : "Counting is paused. Visits are not recorded. The figures below are what was collected before you paused.")
            }

            Section {
                hero(stats)
                tiles(stats)
            }

            let ranked = stats.rankedFilters()
            if !ranked.isEmpty {
                Section {
                    ForEach(ranked) { row in
                        barRow(row)
                    }
                } header: {
                    Text("Filters visitors chose")
                } footer: {
                    let hidden = stats.hiddenFilterCount()
                    if hidden > 0 {
                        Text("\(hidden) more \(hidden == 1 ? "tag" : "tags") with fewer events \(hidden == 1 ? "is" : "are") not shown.")
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    viewModel.showResetConfirmation()
                } label: {
                    Text("Reset Analytics")
                }
                .disabled(viewModel.isSaving)
            } footer: {
                Text("Deletes every recorded event for this album. Your photos and the album itself are untouched. This cannot be undone.")
            }
        }
    }

    /// The live/paused state and the switch for it, on one row — the label says what is
    /// happening now, the button says what tapping it would do.
    private var countingRow: some View {
        HStack {
            Circle()
                .fill(viewModel.isCounting ? Color.green : Color.secondary)
                .frame(width: 10, height: 10)

            Text(viewModel.isCounting ? "Counting visits" : "Counting paused")

            Spacer()

            Button(viewModel.isCounting ? "Pause" : "Resume") {
                viewModel.togglePaused()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isSaving)
        }
    }

    /// The one number the screen leads with.
    private func hero(_ stats: AlbumAnalytics) -> some View {
        VStack(spacing: 4) {
            Text(stats.uniqueVisitors.formatted())
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("Unique visitors")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func tiles(_ stats: AlbumAnalytics) -> some View {
        HStack(alignment: .top, spacing: 0) {
            tile(stats.pageViews, "Page views")
            Divider()
            tile(stats.filterChanges, "Filter changes")
            Divider()
            tile(stats.audioPlays, "Audio plays")
        }
        .padding(.vertical, 4)
    }

    private func tile(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted())
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// One tag: its name, a bar as long as its share of the busiest tag, and the count itself.
    /// The number is the answer — the bar only makes the ranking readable at a glance.
    private func barRow(_ row: AlbumAnalytics.FilterRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.tag)
                    .lineLimit(1)

                Spacer()

                Text(row.count.formatted())
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * row.fraction)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.tag)
        .accessibilityValue("\(row.count) filter changes, \(row.share) percent of all")
    }
}
