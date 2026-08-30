import SwiftUI

struct AlbumFormView: View {
    enum Mode {
        case create
        case edit(Album)

        var title: String {
            switch self {
            case .create: "New Album"
            case .edit: "Edit Album"
            }
        }

        var buttonTitle: String {
            switch self {
            case .create: "Create"
            case .edit: "Save"
            }
        }
    }

    let mode: Mode

    /// `Int?` is the chosen storage backend, nil for the site's own. Always nil when editing:
    /// an album's storage is fixed at creation and the server rejects a change.
    let onSave: (String, String?, Int?) -> Void

    @State private var name: String
    @State private var description: String
    @State private var storageBackendId: Int?

    @StateObject private var storage = StorageBackendsViewModel()

    @Environment(\.dismiss) private var dismiss

    init(mode: Mode, onSave: @escaping (String, String?, Int?) -> Void) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _description = State(initialValue: "")
            _storageBackendId = State(initialValue: nil)
        case let .edit(album):
            _name = State(initialValue: album.name)
            _description = State(initialValue: album.description ?? "")
            _storageBackendId = State(initialValue: album.storageBackendId)
        }
    }

    private var isCreating: Bool {
        if case .create = mode {
            return true
        }
        return false
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Album Details")) {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3 ... 6)
                }

                // Only worth a row once the user has storage of their own; with just the site's
                // storage there is no choice to offer. On edit it is a read-only reminder,
                // because moving an album's photos is not something the server will do.
                if isCreating, storage.hasChoice {
                    Section(
                        header: Text("Storage"),
                        footer: Text("Where this album's photos are stored. This cannot be changed later."),
                    ) {
                        Picker("Store photos in", selection: $storageBackendId) {
                            ForEach(storage.backends) { backend in
                                Text(backend.systemDefault ? "\(backend.name) (default)" : backend.name)
                                    .tag(backend.id as Int?)
                            }
                        }
                    }
                } else if !isCreating, let name = storageBackendName {
                    Section(header: Text("Storage")) {
                        LabeledContent("Stored in", value: name)
                    }
                }

                Section {
                    Button(action: handleSave) {
                        HStack {
                            Spacer()
                            Text(mode.buttonTitle)
                            Spacer()
                        }
                    }
                    .disabled(!isValid)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard isCreating, storage.backends.isEmpty else { return }
                storage.fetchBackends()
            }
            // The list arrives after the form is on screen, so the default is selected here
            // rather than in init — otherwise the picker would open on a blank row.
            .onChange(of: storage.backends) { _, _ in
                if storageBackendId == nil {
                    storageBackendId = storage.systemDefault?.id
                }
            }
        }
    }

    private var storageBackendName: String? {
        if case let .edit(album) = mode {
            return album.storageBackendName
        }
        return nil
    }

    private func handleSave() {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(
            name.trimmingCharacters(in: .whitespacesAndNewlines),
            trimmedDescription.isEmpty ? nil : trimmedDescription,
            isCreating ? storageBackendId : nil,
        )
    }
}
