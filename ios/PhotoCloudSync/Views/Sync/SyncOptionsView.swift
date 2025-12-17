import SwiftUI

struct SyncOptionsView: View {
    @EnvironmentObject private var sync: SyncCoordinator
    @StateObject private var viewModel = SyncOptionsViewModel()
    @Binding var isLoggedIn: Bool

    var body: some View {
        NavigationView {
            List {
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
                    Toggle("Wi‑Fi Only", isOn: $sync.settings.wifiOnly)

                    Stepper(value: $sync.settings.syncLastDays, in: 1 ... 365) {
                        Text("Sync last \(sync.settings.syncLastDays) days")
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
                        .onChange(of: viewModel.selectedAlbum) { newAlbum in
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
