import SwiftUI

struct AlbumListView: View {
    @StateObject private var viewModel = AlbumsViewModel()
    @State private var showingCreateSheet = false
    @State private var albumToEdit: Album?

    /// Whether the tiles can be dragged into a different order.
    ///
    /// A mode rather than something always on, because a tile carries three long-press gestures'
    /// worth of behaviour already: tapping opens the album and a long press opens the context
    /// menu, and a drag that starts the same way as that menu is a coin toss. While this is on the
    /// tiles neither open nor show their menu — they only move.
    @State private var isReordering = false

    /// The tile currently under the finger, so it can be dimmed while it travels.
    @State private var draggedAlbumId: Int?

    /// The tile the dragged one would land on.
    @State private var dropTargetAlbumId: Int?

    /// The link handed to the system share sheet. Owned by this screen, not by the card: a sheet
    /// presented from a context menu goes away with the menu.
    @State private var sharingLink: ShareableLink?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// How big the album cards are drawn. A reading preference, not a fact about the account, so
    /// it lives in app storage; separate from the key the photo grid uses because the web app
    /// keeps the two switches apart as well.
    @AppStorage("albumGridSize") private var gridSize: GridSizeMode = .medium

    private var columns: [GridItem] {
        AdaptiveGrid.cardColumns(horizontalSizeClass, size: gridSize)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading, viewModel.albums.isEmpty {
                    ProgressView("Loading albums...")
                        .padding()
                } else if viewModel.albums.isEmpty {
                    emptyStateView
                } else {
                    if isReordering {
                        Text("Drag a tile onto the place it should take. Every move is saved right away.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.albums) { album in
                            if isReordering {
                                reorderableTile(for: album)
                            } else {
                                NavigationLink(destination: AlbumDetailView(
                                    album: album,
                                    onDeleted: { viewModel.albums.removeAll { $0.id == album.id } },
                                    onChanged: { viewModel.replace($0) },
                                )) {
                                    card(for: album)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding()
                }
            }
            .gridZoom($gridSize)
            .navigationTitle("Albums")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(
                        action: { showingCreateSheet = true },
                        label: { Image(systemName: "plus") },
                    )
                }
                // Only worth offering once there are two tiles to put in an order.
                if viewModel.albums.count > 1 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(isReordering ? "Done" : "Reorder") {
                            isReordering.toggle()
                            draggedAlbumId = nil
                            dropTargetAlbumId = nil
                        }
                        .accessibilityLabel(isReordering ? "Finish reordering" : "Reorder albums")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        GridSizePicker(size: $gridSize)
                    } label: {
                        Image(systemName: gridSize.systemImage)
                    }
                    .accessibilityLabel("Card size")
                    .disabled(isReordering)
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
                AlbumFormView(mode: .create) { name, description, storageBackendId in
                    viewModel.createAlbum(
                        name: name,
                        description: description,
                        storageBackendId: storageBackendId,
                    ) { success in
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
                AlbumFormView(mode: .edit(album)) { name, description, _ in
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

    /// One album tile. The context menu is dropped while reordering, so the long press belongs to
    /// the drag and nothing else.
    private func card(for album: Album) -> some View {
        AlbumCardView(
            album: album,
            size: gridSize,
            reordering: isReordering,
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
            onDuplicate: {
                viewModel.showDuplicateConfirmation(for: album) {
                    viewModel.duplicateAlbum(id: album.id)
                }
            },
            onDelete: {
                viewModel.showDeleteConfirmation(for: album) {
                    viewModel.deleteAlbum(id: album.id) { _ in }
                }
            },
        )
    }

    /// A tile that can be picked up and dropped onto another one.
    ///
    /// The payload is the album id as text. Anything else dropped on the grid — a word from
    /// another app, an id from an album that has since been deleted — fails the lookup in
    /// ``AlbumsViewModel/moveAlbum(draggedId:onto:)`` and is ignored.
    private func reorderableTile(for album: Album) -> some View {
        card(for: album)
            .opacity(draggedAlbumId == album.id ? 0.4 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: dropTargetAlbumId == album.id ? 3 : 0),
            )
            .draggable(String(album.id)) {
                // The drag preview. Not the whole card: a cover-sized image under the finger
                // hides the row it is being dropped into.
                Text(album.name)
                    .font(.caption)
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .onAppear { draggedAlbumId = album.id }
            }
            .dropDestination(for: String.self) { items, _ in
                draggedAlbumId = nil
                dropTargetAlbumId = nil
                guard let droppedId = items.first.flatMap(Int.init) else { return false }
                viewModel.moveAlbum(draggedId: droppedId, onto: album.id)
                return true
            } isTargeted: { targeted in
                dropTargetAlbumId = targeted ? album.id : nil
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

    /// How wide the card is being drawn. At ``GridSizeMode/small`` three cards share a phone
    /// screen, and the headline title with 12 points of padding around it leaves the cover
    /// barely bigger than its own caption — so the chrome shrinks with the card.
    let size: GridSizeMode

    /// True while the shelf is being reordered. The card then shows a grip instead of offering
    /// its context menu, so the long press starts a drag rather than a menu.
    var reordering: Bool = false

    let onEdit: () -> Void

    /// Opens or closes public access. Kept next to Share in the menu because it is the switch
    /// that decides whether sharing does anything at all.
    let onTogglePublished: () -> Void

    /// Raised to the list screen, which owns the share sheet.
    let onShare: () -> Void

    /// Copies the album into a new one. Sits above Delete in the menu and carries no destructive
    /// role: it adds an album, it never touches this one.
    let onDuplicate: () -> Void

    let onDelete: () -> Void

    @State private var showingActions = false

    private func albumCoverURL(token: String) -> URL? {
        let baseURL = AppConfiguration.apiBaseURL
        var components = URLComponents(url: baseURL.appendingPathComponent("api/i/\(token)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "size", value: "medium")]
        return components?.url
    }

    @ViewBuilder
    var body: some View {
        if reordering {
            cardBody
        } else {
            cardBody.contextMenu { menuItems }
        }
    }

    private var cardBody: some View {
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
                    .font(size == .small ? .caption : .headline)
                    .fontWeight(size == .small ? .semibold : .regular)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Count and cover date on one line: a third-width tile has no room for two, and
                // the date is dropped rather than wrapped when the album holds no image.
                HStack(spacing: 4) {
                    Text("\(album.imageCount ?? 0) photo\(album.imageCount == 1 ? "" : "s")")
                    if let coverDate = album.coverDate {
                        Text("·")
                        Text(coverDate, format: .dateTime.day().month(.abbreviated).year())
                    }
                }
                .font(size == .small ? .caption2 : .caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
        }
        .padding(size == .small ? 6 : 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(alignment: .bottomTrailing) {
            // Says the tile can be dragged. Only while that is true.
            if reordering {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(.thinMaterial, in: Circle())
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var menuItems: some View {
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

        Button(action: onDuplicate) {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }
}
