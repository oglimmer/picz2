import SwiftUI

struct AlbumListView: View {
    @StateObject private var viewModel = AlbumsViewModel()
    @State private var showingCreateSheet = false
    @State private var showingEditSheet = false
    @State private var albumToEdit: Album?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                if viewModel.isLoading, viewModel.albums.isEmpty {
                    ProgressView("Loading albums...")
                        .padding()
                } else if viewModel.albums.isEmpty {
                    emptyStateView
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.albums) { album in
                            NavigationLink(destination: AlbumDetailView(album: album)) {
                                AlbumCardView(
                                    album: album,
                                    onEdit: {
                                        albumToEdit = album
                                        showingEditSheet = true
                                    },
                                    onDelete: {
                                        viewModel.showDeleteConfirmation(for: album) {
                                            viewModel.deleteAlbum(id: album.id) { _ in }
                                        }
                                    },
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Albums")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(
                        action: { showingCreateSheet = true },
                        label: { Image(systemName: "plus") },
                    )
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(
                        action: { viewModel.fetchAlbums() },
                        label: { Image(systemName: "arrow.clockwise") },
                    )
                    .disabled(viewModel.isLoading)
                }
            }
            .refreshable {
                await viewModel.refreshAlbums()
            }
            .sheet(isPresented: $showingCreateSheet) {
                AlbumFormView(mode: .create) { name, description in
                    viewModel.createAlbum(name: name, description: description) { success in
                        if success {
                            showingCreateSheet = false
                        }
                    }
                }
            }
            .sheet(item: $albumToEdit) { album in
                AlbumFormView(mode: .edit(album)) { name, description in
                    viewModel.updateAlbum(id: album.id, name: name, description: description) { success in
                        if success {
                            albumToEdit = nil
                        }
                    }
                }
            }
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

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Albums Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create your first album to start organizing your photos")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(
                action: { showingCreateSheet = true },
                label: {
                    Label("Create Album", systemImage: "plus.circle.fill")
                        .font(.headline)
                },
            )
            .buttonStyle(.borderedProminent)
            .padding(.top, 10)
        }
        .padding()
    }
}

// MARK: - Album Card View

struct AlbumCardView: View {
    let album: Album
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showingActions = false

    private func albumCoverURL(token: String) -> URL? {
        let baseURL = AppConfiguration.apiBaseURL
        var components = URLComponents(url: baseURL.appendingPathComponent("api/i/\(token)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "size", value: "medium")]
        return components?.url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Album cover image
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)

                if let coverImageToken = album.coverImageToken,
                   let coverURL = albumCoverURL(token: coverImageToken)
                {
                    // Show cover image if available
                    AuthenticatedImage(url: coverURL)
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                } else {
                    // Placeholder for empty album
                    VStack(spacing: 8) {
                        Text("📁")
                            .font(.system(size: 40))
                        Text("Empty Album")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .aspectRatio(1.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let imageCount = album.imageCount {
                    Text("\(imageCount) photo\(imageCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("0 photos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
