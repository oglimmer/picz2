import Photos
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sync: SyncCoordinator
    @State private var authStatus: PHAuthorizationStatus = .notDetermined
    @State private var isLoggedIn: Bool = false
    @State private var albums: [Album] = []
    @State private var isLoadingAlbums: Bool = false
    @State private var selectedAlbum: Album?

    var body: some View {
        Group {
            if isLoggedIn {
                mainView
            } else {
                LoginView(isLoggedIn: $isLoggedIn)
            }
        }
        .onAppear {
            print("ContentView: body.onAppear - checking login status")
            checkLoginStatus()
        }
    }

    private var mainView: some View {
        NavigationView {
            List {
                Section(header: Text("Permissions")) {
                    HStack {
                        Text("Photo Access")
                        Spacer()
                        Text(statusText(authStatus))
                            .foregroundColor(authStatus == .authorized || authStatus == .limited ? .green : .orange)
                    }
                    Button("Request Access") { requestAccess() }
                        .disabled(authStatus == .authorized || authStatus == .limited)
                }

                Section(header: Text("Settings")) {
                    Toggle("Wi‑Fi Only", isOn: $sync.settings.wifiOnly)

                    Stepper(value: $sync.settings.syncLastDays, in: 1 ... 365) {
                        Text("Sync last \(sync.settings.syncLastDays) days")
                    }

                    Button("Refresh Albums") {
                        fetchAlbums()
                    }
                    .disabled(isLoadingAlbums)

                    if isLoadingAlbums {
                        HStack {
                            Text("Loading albums...")
                            Spacer()
                            ProgressView()
                        }
                    } else if albums.isEmpty {
                        Text("No albums found")
                    } else {
                        Picker("Album", selection: $selectedAlbum) {
                            ForEach(albums) { album in
                                Text(album.name).tag(album as Album?)
                            }
                        }
                        .onChange(of: selectedAlbum) { newAlbum in
                            if let album = newAlbum {
                                sync.settings.albumId = album.id
                                sync.settings.selectedAlbumName = album.name
                                // Update target album on server
                                updateTargetAlbum(albumId: album.id)
                                // Start syncing now that an album has been selected
                                sync.start()
                            }
                        }
                    }

                    Button("Logout") {
                        logout()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Photo Cloud Sync")
            .onAppear {
                print("ContentView: mainView.onAppear called")
                requestAccessIfNeeded()
                sync.start()
                fetchAlbums()
            }
        }
    }

    private func statusText(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Authorized"
        case .limited: return "Limited"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not determined"
        @unknown default: return "Unknown"
        }
    }

    private func requestAccessIfNeeded() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { authStatus = status }
        }
    }

    private func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { authStatus = status }
        }
    }

    private func checkLoginStatus() {
        let credentials = KeychainHelper.shared.load()
        isLoggedIn = credentials != nil
        print("ContentView: checkLoginStatus - isLoggedIn = \(isLoggedIn)")
    }

    private func fetchAlbums() {
        guard let credentials = KeychainHelper.shared.load() else { return }

        isLoadingAlbums = true
        let api = APIClient(username: credentials.username, password: credentials.password)

        // Fetch target album from server first
        api.getTargetAlbum { targetResult in
            // Then fetch albums list
            api.fetchAlbums { albumsResult in
                DispatchQueue.main.async {
                    isLoadingAlbums = false
                    switch albumsResult {
                    case let .success(fetchedAlbums):
                        albums = fetchedAlbums

                        // If server has a target album set, use that
                        if case let .success(targetAlbumId) = targetResult, let targetId = targetAlbumId {
                            selectedAlbum = albums.first { $0.id == targetId }
                            if let album = selectedAlbum {
                                sync.settings.albumId = album.id
                                sync.settings.selectedAlbumName = album.name
                            }
                        }
                        // Otherwise restore previously selected album from local settings
                        else if let savedAlbumName = sync.settings.selectedAlbumName {
                            selectedAlbum = albums.first { $0.name == savedAlbumName }
                        }
                    case let .failure(error):
                        print("Failed to fetch albums: \(error)")
                    }
                }
            }
        }
    }

    private func updateTargetAlbum(albumId: Int) {
        guard let credentials = KeychainHelper.shared.load() else { return }

        let api = APIClient(username: credentials.username, password: credentials.password)

        api.setTargetAlbum(albumId: albumId) { result in
            switch result {
            case .success:
                print("ContentView: Target album updated on server: \(albumId)")
            case let .failure(error):
                print("ContentView: Failed to update target album on server: \(error)")
            }
        }
    }

    private func logout() {
        // Clear keychain credentials
        KeychainHelper.shared.delete()

        // Clear all synced images data
        UploadStore.shared.clear()

        // Clear all settings (album selection, last sync date, etc.)
        sync.settings.clear()

        // Clear sync queue and reset metrics
        sync.clearQueue()
        sync.metrics = SyncCoordinator.Metrics()

        // Clear UI state
        isLoggedIn = false
        albums = []
        selectedAlbum = nil
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(SyncCoordinator.shared)
    }
}
