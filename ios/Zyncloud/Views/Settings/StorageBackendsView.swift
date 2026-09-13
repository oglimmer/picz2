import SwiftUI

/// "Bring your own storage": the list of places albums can be stored, and the form to add one.
///
/// The site's own storage is always first and is read-only — it is what every album uses unless
/// its owner chose otherwise when creating it. A user's own entry can be edited or removed, but
/// only while no album still holds photos there.
struct StorageBackendsView: View {
    @StateObject private var viewModel = StorageBackendsViewModel()
    @State private var editing: StorageBackendFormView.Mode?

    var body: some View {
        List {
            Section(
                footer: Text("Photos are stored on this site by default, up to the limit shown. "
                    + "Got a home server — a MinIO box in your home lab, or a little machine humming "
                    + "in the living room? Add it, and the files of an album live there instead, "
                    + "with no limit from us. You choose the storage when you create an album; it "
                    + "cannot be changed afterwards."),
            ) {
                ForEach(viewModel.backends) { backend in
                    row(for: backend)
                }
            }

            Section {
                Button("Add your own storage") {
                    editing = .create
                }
            }

            if viewModel.isLoading {
                Section {
                    HStack {
                        Text("Working…")
                            .foregroundColor(.secondary)
                        Spacer()
                        ProgressView()
                    }
                }
            }
        }
        .navigationTitle("Photo Storage")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { mode in
            StorageBackendFormView(mode: mode, viewModel: viewModel) {
                editing = nil
            }
        }
        .alert(state: $viewModel.alertState)
        .onAppear {
            if viewModel.backends.isEmpty {
                viewModel.fetchBackends()
            }
        }
    }

    private func row(for backend: StorageBackend) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(backend.name)
                    .font(.body)
                if backend.systemDefault {
                    Text("Default")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text(backend.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(backend.albumCount == 1 ? "1 album" : "\(backend.albumCount) albums")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Only the site's own storage has a limit; a user's own bucket shows none.
            if let summary = backend.quotaSummary {
                ProgressView(value: backend.usedFraction)
                    .tint(backend.usedFraction >= 1 ? .red : .accentColor)
                    .padding(.top, 2)
                Text(summary)
                    .font(.caption2)
                    .foregroundColor(backend.usedFraction >= 1 ? .red : .secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // The site's own storage has nothing editable: its credentials live in the server's
            // configuration, not in a row anyone can see.
            guard !backend.systemDefault else { return }
            editing = .edit(backend)
        }
        .swipeActions(edge: .trailing) {
            if !backend.systemDefault {
                Button("Remove", role: .destructive) {
                    viewModel.delete(backend)
                }
                .disabled(backend.albumCount > 0)
            }
        }
    }
}

/// Add or edit one storage backend.
///
/// The secret key is write-only on the server, so an edit starts with the field empty and an
/// empty field means "keep the saved key" — the form never has the real value to show.
struct StorageBackendFormView: View {
    enum Mode: Identifiable {
        case create
        case edit(StorageBackend)

        var id: Int {
            switch self {
            case .create: 0
            case let .edit(backend): backend.id
            }
        }

        var title: String {
            switch self {
            case .create: "Add Storage"
            case .edit: "Edit Storage"
            }
        }

        var backendId: Int? {
            switch self {
            case .create: nil
            case let .edit(backend): backend.id
            }
        }
    }

    let mode: Mode
    @ObservedObject var viewModel: StorageBackendsViewModel
    let onFinished: () -> Void

    @State private var name: String
    @State private var endpoint: String
    @State private var region: String
    @State private var bucket: String
    @State private var accessKey: String
    @State private var secretKey: String
    @State private var pathStyleAccess: Bool

    @Environment(\.dismiss) private var dismiss

    init(mode: Mode, viewModel: StorageBackendsViewModel, onFinished: @escaping () -> Void) {
        self.mode = mode
        self.viewModel = viewModel
        self.onFinished = onFinished

        switch mode {
        case .create:
            // The copy is written for a self-hosted MinIO, and these are its settings. Nothing
            // is locked, so any other server that speaks the same protocol works as well.
            _name = State(initialValue: "")
            _endpoint = State(initialValue: "")
            _region = State(initialValue: "us-east-1")
            _bucket = State(initialValue: "")
            _accessKey = State(initialValue: "")
            _secretKey = State(initialValue: "")
            _pathStyleAccess = State(initialValue: true)
        case let .edit(backend):
            _name = State(initialValue: backend.name)
            _endpoint = State(initialValue: backend.endpoint ?? "")
            _region = State(initialValue: backend.region ?? "us-east-1")
            _bucket = State(initialValue: backend.bucket ?? "")
            _accessKey = State(initialValue: backend.accessKey ?? "")
            _secretKey = State(initialValue: "")
            _pathStyleAccess = State(initialValue: backend.pathStyleAccess)
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !endpoint.trimmingCharacters(in: .whitespaces).isEmpty
            && !bucket.trimmingCharacters(in: .whitespaces).isEmpty
            && !accessKey.trimmingCharacters(in: .whitespaces).isEmpty
            && (mode.backendId != nil || !secretKey.isEmpty)
    }

    private var formPayload: StorageBackendBody {
        StorageBackendBody(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            region: region.trimmingCharacters(in: .whitespacesAndNewlines),
            bucket: bucket.trimmingCharacters(in: .whitespacesAndNewlines),
            accessKey: accessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            // Omitted rather than sent empty: the server reads "absent" as "keep the stored one".
            secretKey: secretKey.isEmpty ? nil : secretKey,
            pathStyleAccess: pathStyleAccess,
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // A real row rather than a lone footer: a Section with no content renders as an
                // empty band on some iOS versions, and this is the paragraph people most need to
                // read before they open the MinIO Console.
                Section {
                    Text("Your photos, on the server in your own home. Before you start, create a "
                        + "bucket on your home server's MinIO and an access key that may read, write "
                        + "and delete in it — this app does not create the bucket for you. Keep the "
                        + "bucket private: the photo server fetches the photos from your server and "
                        + "passes them on, so nothing on your server needs to be public.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section(
                    header: Text("Storage"),
                    footer: Text("Name is just a label for you, like \"Home server\"; it appears in "
                        + "the album picker. The endpoint is the API address of the MinIO on your "
                        + "home server (often port 9000) — not the Console address, and not the "
                        + "bucket's address. It has to be reachable from the internet: the photo "
                        + "server calls your home, so an address that only works on your home Wi‑Fi "
                        + "is not enough. The bucket is its name on its own, no URL and no slashes."),
                ) {
                    TextField("Name", text: $name)
                    TextField("Endpoint URL", text: $endpoint, prompt: Text("https://abc123def456.myfritz.net"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Bucket", text: $bucket)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(
                    header: Text("Region"),
                    footer: Text("A home server rarely cares about this: MinIO ignores the region "
                        + "unless you set one. Leave \"us-east-1\" unless you changed it on your server."),
                ) {
                    TextField("Region", text: $region)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(
                    header: Text("Credentials"),
                    footer: Text("Open the MinIO Console on your home server: Access Keys → Create "
                        + "access key.\n\nThe secret key is stored encrypted and never shown again. "
                        + "MinIO also shows it only once, when you create the key, so copy it then. "
                        + "Leave it empty when editing to keep the saved one."),
                ) {
                    TextField("Access key", text: $accessKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Secret key", text: $secretKey)
                }

                Section(
                    footer: Text("Puts the bucket in the path (endpoint/bucket) instead of in the "
                        + "hostname. The MinIO on a home server needs this on. Turn it off only if "
                        + "you set up your server to expect the bucket name in the hostname."),
                ) {
                    Toggle("Path-style addressing", isOn: $pathStyleAccess)
                }

                if let result = viewModel.testResult {
                    Section {
                        if result.ok {
                            Label(
                                "Connection works — a test file was written, read and deleted.",
                                systemImage: "checkmark.circle",
                            )
                            .foregroundColor(.green)
                        } else {
                            Label(
                                "Failed at \(result.failedStep ?? "connect"): \(result.message ?? "unknown reason")",
                                systemImage: "exclamationmark.triangle",
                            )
                            .foregroundColor(.red)
                        }
                    }
                }

                Section {
                    Button("Test connection") {
                        viewModel.test(id: mode.backendId, body: formPayload)
                    }
                    .disabled(!isValid || viewModel.isLoading)

                    Button(action: handleSave) {
                        HStack {
                            Spacer()
                            Text("Save")
                            Spacer()
                        }
                    }
                    .disabled(!isValid || viewModel.isLoading)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                        onFinished()
                    }
                }
            }
        }
    }

    private func handleSave() {
        let payload = formPayload
        if let id = mode.backendId {
            viewModel.update(id: id, body: payload) { saved in
                if saved {
                    dismiss()
                    onFinished()
                }
            }
        } else {
            viewModel.create(payload) { saved in
                if saved {
                    dismiss()
                    onFinished()
                }
            }
        }
    }
}
