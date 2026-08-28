import Combine
import SwiftUI
import UIKit

struct SyncOptionsView: View {
    @StateObject private var viewModel = SyncOptionsViewModel()
    /// Photo access can be changed in iOS Settings while the app sits in the background, so the
    /// status is re-read on every return to `.active` as well as on first appearance.
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    /// Observed directly, not reached through `sync.settings` (§5.5).
    ///
    /// `Settings` is an `ObservableObject` held inside another one. Mutating a property of the
    /// inner object fires *its* objectWillChange, not the coordinator's — so a `$sync.settings.x`
    /// binding wrote the new value but SwiftUI had no reason to re-render, and the switch could
    /// visibly snap back. Observing the inner object is what makes the toggles honest.
    @ObservedObject private var settings = Settings.shared
    @Binding var isLoggedIn: Bool

    /// Step 1 of the account delete — the "are you sure" sheet.
    @State private var showDeleteAccountConfirm = false
    /// Step 2 — set only once step 1 was confirmed, which swaps the row for a final warning.
    ///
    /// The web app stacks two modal confirms here. On iOS the second one cannot be a second
    /// `.alert`: this view already carries `.alert(state:)` for `alertState`, and two alert
    /// modifiers on one view fight over the same presentation slot — the later one silently
    /// wins. So the final warning is an inline armed state instead. Same two deliberate
    /// destructive taps, one presenter.
    @State private var deleteAccountArmed = false

    var body: some View {
        NavigationStack {
            List {
                // Photo Access Section — shown only while there is something to fix. Full
                // access is the steady state and needs no row; `.limited` is *not* full access
                // and stays visible, because the cost of it is invisible otherwise.
                if viewModel.showsPermissionsSection {
                    Section(header: Text("Permissions")) {
                        HStack {
                            Text("Photo Access")
                            Spacer()
                            Text(viewModel.photoAccessStatusText)
                                .foregroundColor(viewModel.photoAccessColor == "green" ? .green : (viewModel.photoAccessColor == "red" ? .red : .orange))
                        }

                        if let hint = viewModel.photoAccessHint {
                            Text(hint)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        if viewModel.canRequestAccess {
                            Button("Request Access") {
                                viewModel.requestPhotoAccess()
                            }
                        } else if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            // Denied, restricted and limited cannot be re-prompted in-app; the
                            // only way out is the system settings page for this app.
                            Button("Open Settings") {
                                openURL(settingsURL)
                            }
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

                // Account-level gallery settings. These live on the user, not on this
                // device, so they are the same values the web app edits from its account menu.
                Section(header: Text("Gallery Settings")) {
                    NavigationLink("Narration Languages") {
                        NarrationLanguagesView()
                    }

                    NavigationLink("Tags") {
                        TagManagerView()
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

                Section(
                    header: Text("Danger Zone"),
                    footer: Text("Deleting your account removes your albums, photos, tags and settings from the server for good. There is no undo and no export afterwards."),
                ) {
                    if viewModel.isDeletingAccount {
                        HStack {
                            Text("Deleting account…")
                                .foregroundColor(.secondary)
                            Spacer()
                            ProgressView()
                        }
                    } else if deleteAccountArmed {
                        Text("Final warning — this cannot be undone.")
                            .font(.footnote)
                            .foregroundColor(.red)

                        Button("Yes, Delete Everything") {
                            deleteAccountArmed = false
                            viewModel.deleteAccount {
                                isLoggedIn = false
                            }
                        }
                        .foregroundColor(.red)

                        Button("Cancel") {
                            deleteAccountArmed = false
                        }
                    } else {
                        Button("Delete Account") {
                            showDeleteAccountConfirm = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Sync Options")
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteAccountConfirm,
                titleVisibility: .visible,
            ) {
                Button("Delete My Account", role: .destructive) {
                    deleteAccountArmed = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all your albums, all your photos, all your tags and all your settings. This action cannot be undone.")
            }
            .alert(state: $viewModel.alertState)
            .onAppear {
                viewModel.checkPhotoAccess()
                if viewModel.albums.isEmpty {
                    viewModel.fetchAlbums()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.checkPhotoAccess()
                }
            }
        }
    }
}
