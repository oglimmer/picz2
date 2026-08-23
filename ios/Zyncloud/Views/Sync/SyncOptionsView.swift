import SwiftUI

struct SyncOptionsView: View {
    @EnvironmentObject private var sync: SyncCoordinator
    @StateObject private var viewModel = SyncOptionsViewModel()
    @ObservedObject private var taskLog = BackgroundTaskLog.shared
    /// Observed directly, not reached through `sync.settings` (§5.5).
    ///
    /// `Settings` is an `ObservableObject` held inside another one. Mutating a property of the
    /// inner object fires *its* objectWillChange, not the coordinator's — so a `$sync.settings.x`
    /// binding wrote the new value but SwiftUI had no reason to re-render, and the switch could
    /// visibly snap back. Observing the inner object is what makes the toggles honest.
    @ObservedObject private var settings = Settings.shared
    @Binding var isLoggedIn: Bool

    /// "Never" is a real answer here, and the most important one to read at a glance — so it is
    /// spelled out rather than shown as an empty value.
    private static func stamp(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }

    var body: some View {
        NavigationView {
            List {
                // Sync status. §3.3 was undetectable in code and would have been obvious here:
                // background tasks were only ever scheduled at launch, and the only symptom was
                // sync quietly stopping. Scheduled and run are shown separately because "iOS has
                // not granted us time yet" and "we never asked" are different faults.
                Section(
                    header: Text("Sync Status"),
                    footer: sync.metrics.skippedTooLarge > 0
                        ? Text("Some files are larger than this server accepts, so they were not backed up. Open the Sync Log to see which ones and how big they are.")
                        : Text("")
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
                    header: Text("Background Tasks"),
                    footer: Text(taskLog.hasScheduledButNeverRun
                        ? "Scheduled, but iOS has not granted background time yet. This is normal for a while after install; if it persists for days, scheduling is broken."
                        : "iOS decides when these run. Long gaps are normal; \"never\" is not.")
                ) {
                    LabeledContent("Last scheduled", value: Self.stamp(taskLog.lastScheduled))
                    LabeledContent("Refresh last run",
                                   value: Self.stamp(taskLog.lastRun(.refresh)))
                    LabeledContent("Processing last run",
                                   value: Self.stamp(taskLog.lastRun(.processing)))
                    LabeledContent("Run count",
                                   value: "\(taskLog.runCount(.refresh) + taskLog.runCount(.processing))")
                }

                // Photo Access Section
                Section(header: Text("Permissions")) {
                    HStack {
                        Text("Photo Access")
                        Spacer()
                        Text(viewModel.photoAccessStatusText)
                            .foregroundColor(viewModel.photoAccessColor == "green" ? .green : (viewModel.photoAccessColor == "red" ? .red : .orange))
                    }

                    if viewModel.canRequestAccess {
                        Button("Request Access") {
                            viewModel.requestPhotoAccess()
                        }
                    }
                }

                // Sync Settings Section
                Section(header: Text("Sync Settings")) {
                    Toggle("Wi‑Fi Only", isOn: $settings.wifiOnly)

                    Stepper(value: $settings.syncLastDays, in: 1 ... 365) {
                        Text("Sync last \(settings.syncLastDays) days")
                    }
                }

                // Phase 5 — TUS resumable uploads. Hidden under Advanced because the multipart
                // path is the documented stable behaviour; TUS is opt-in until R3 (TestFlight
                // default-on) ships. SyncCoordinator.shouldUseTus() requires both this flag AND
                // server-advertised tus.enabled, so flipping it on a server that hasn't enabled
                // TUS is a no-op (silently falls back to multipart).
                Section(
                    header: Text("Advanced"),
                    footer: Text("Resumable uploads recover from network drops mid-file instead of restarting from zero. Requires server support; falls back to standard uploads automatically when unavailable."),
                ) {
                    Toggle("Resumable Uploads (TUS)", isOn: $settings.useTus)
                }

                // Album Selection Section
                Section(header: Text("Target Album")) {
                    Button("Refresh Albums") {
                        viewModel.fetchAlbums()
                    }
                    .disabled(viewModel.isLoadingAlbums)

                    if viewModel.isLoadingAlbums {
                        HStack {
                            Text("Loading albums...")
                            Spacer()
                            ProgressView()
                        }
                    } else if viewModel.albums.isEmpty {
                        Text("No albums found")
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Album", selection: $viewModel.selectedAlbum) {
                            ForEach(viewModel.albums) { album in
                                Text(album.name).tag(album as Album?)
                            }
                        }
                        .onChange(of: viewModel.selectedAlbum) { _, newAlbum in
                            if let album = newAlbum {
                                viewModel.selectAlbum(album)
                            }
                        }
                    }
                }

                // Account Section
                Section(header: Text("Data Management")) {
                    Button("Sync Now") {
                        viewModel.syncNow()
                    }

                    Button("Clear Local Cache") {
                        viewModel.clearLocalCache()
                    }
                    .foregroundColor(.orange)

                    Button("Logout") {
                        viewModel.logout {
                            isLoggedIn = false
                        }
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Sync Options")
            .alert(item: $viewModel.alertState) { alertState in
                if let primaryButton = alertState.primaryButton,
                   let secondaryButton = alertState.secondaryButton
                {
                    Alert(
                        title: Text(alertState.title),
                        message: Text(alertState.message),
                        primaryButton: .destructive(Text(primaryButton.title), action: primaryButton.action),
                        secondaryButton: .cancel(Text(secondaryButton.title), action: secondaryButton.action),
                    )
                } else {
                    Alert(
                        title: Text(alertState.title),
                        message: Text(alertState.message),
                    )
                }
            }
            .onAppear {
                if viewModel.albums.isEmpty {
                    viewModel.fetchAlbums()
                }
            }
        }
    }
}
