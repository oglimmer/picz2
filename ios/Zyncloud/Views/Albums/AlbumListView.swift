import SwiftUI

struct AlbumListView: View {
    @StateObject private var viewModel = AlbumsViewModel()
    @State private var showingCreateSheet = false
    @State private var albumToEdit: Album?

    /// The link handed to the system share sheet. Owned by this screen, not by the card: a sheet
    /// presented from a context menu goes away with the menu.
    @State private var sharingLink: ShareableLink?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading, viewModel.albums.isEmpty {
                    ProgressView("Loading albums...")
                        .padding()
                } else if viewModel.albums.isEmpty {
                    emptyStateView
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.albums) { album in
                            NavigationLink(destination: AlbumDetailView(
                                album: album,
                                onDeleted: { viewModel.albums.removeAll { $0.id == album.id } },
                                onChanged: { viewModel.replace($0) },
                            )) {
                                AlbumCardView(
                                    album: album,
                                    onEdit: {
                                        albumToEdit = album
                                    },
                                    onTogglePublished: {
                                        viewModel.setPublished(id: album.id, published: !album.isPublished)
                                    },
                                    onShare: {
                                        if let shareToken = album.shareToken,
                                           let shareURL = AppConfiguration.publicAlbumURL(shareToken: shareToken)
                                        {
                                            sharingLink = ShareableLink(url: shareURL)
                                        }
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
            .sheet(item: $sharingLink) { link in
                ShareSheet(items: [link.url])
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
            .alert(state: $viewModel.alertState)
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

    /// Opens or closes public access. Kept next to Share in the menu because it is the switch
    /// that decides whether sharing does anything at all.
    let onTogglePublished: () -> Void

    /// Raised to the list screen, which owns the share sheet.
    let onShare: () -> Void
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
                // A private album is one nobody outside the account can open. Saying so on the
                // tile is the difference between a deliberate draft and a share link the owner
                // believes is working.
                if !album.isPublished {
                    VStack {
                        HStack {
                            Text("PRIVATE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.black.opacity(0.65)))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
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

            Button(action: onTogglePublished) {
                album.isPublished
                    ? Label("Make Private", systemImage: "eye.slash")
                    : Label("Make Public", systemImage: "eye")
            }

            // Only when the link actually opens. Handing out a URL that 404s is worse than not
            // offering to share: the owner would hear about it from whoever it failed for.
            if album.shareToken != nil, album.isPublished {
                Button(action: onShare) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
