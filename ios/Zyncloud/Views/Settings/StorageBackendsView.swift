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
                footer: Text("Photos are stored on this site by default, up to the limit shown. Add your own S3-compatible storage to keep the files in your bucket instead, with no limit from us. You choose the storage when you create an album; it cannot be changed afterwards."),
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

    /// Which preset the form is following. A convenience only — nothing about it is sent, and the
    /// server sees the resulting endpoint/region/path-style like any hand-typed set.
    @State private var providerId: String

    @Environment(\.dismiss) private var dismiss

    init(mode: Mode, viewModel: StorageBackendsViewModel, onFinished: @escaping () -> Void) {
        self.mode = mode
        self.viewModel = viewModel
        self.onFinished = onFinished

        switch mode {
        case .create:
            // Start on a preset rather than on empty fields: an endpoint shape is far easier to
            // correct than to invent, and every provider writes it differently.
            let preset = StorageProvider.all[0]
            _providerId = State(initialValue: preset.id)
            _name = State(initialValue: "")
            _endpoint = State(initialValue: preset.endpointTemplate)
            _region = State(initialValue: preset.region)
            _bucket = State(initialValue: "")
            _accessKey = State(initialValue: "")
            _secretKey = State(initialValue: "")
            _pathStyleAccess = State(initialValue: preset.pathStyleAccess)
        case let .edit(backend):
            // Guessed from the saved endpoint so the hints describe the provider this backend
            // actually points at, not whichever one is first in the list.
            _providerId = State(
                initialValue: StorageProvider.guess(fromEndpoint: backend.endpoint ?? "").id,
            )
            _name = State(initialValue: backend.name)
            _endpoint = State(initialValue: backend.endpoint ?? "")
            _region = State(initialValue: backend.region ?? "us-east-1")
            _bucket = State(initialValue: backend.bucket ?? "")
            _accessKey = State(initialValue: backend.accessKey ?? "")
            _secretKey = State(initialValue: "")
            _pathStyleAccess = State(initialValue: backend.pathStyleAccess)
        }
    }

    private var provider: StorageProvider {
        StorageProvider.named(providerId)
    }

    /// Copy the chosen preset into the connection fields. Only the three it knows — name, bucket
    /// and the keys are the user's, and clearing them on a stray change of the picker would throw
    /// away typing.
    private func applyProvider() {
        let preset = provider
        endpoint = preset.endpointTemplate
        region = preset.region
        pathStyleAccess = preset.pathStyleAccess
        viewModel.testResult = nil
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
                Section(
                    header: Text("Provider"),
                    footer: Text("Picking one fills in the endpoint shape and the right settings. You can still edit everything below."),
                ) {
                    Picker("Provider", selection: $providerId) {
                        ForEach(StorageProvider.all) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .onChange(of: providerId) { _, _ in applyProvider() }
                }

                // A real row rather than a lone footer: a Section with no content renders as an
                // empty band on some iOS versions, and this is the paragraph people most need to
                // read before they go hunting in a provider console.
                Section {
                    Text("You need a bucket that already exists, and a key pair that may read, write and delete in it. This app does not create the bucket for you. Keep the bucket private — photos are served through short-lived signed links, so nothing needs to be public.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section(
                    header: Text("Storage"),
                    footer: Text("Name is just a label for you; it appears in the album picker. The endpoint is your provider's S3 address, not your bucket's — replace anything in <angle brackets>. The bucket is its name on its own, no URL and no slashes."),
                ) {
                    TextField("Name", text: $name)
                    TextField("Endpoint URL", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Bucket", text: $bucket)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(
                    header: Text("Region"),
                    footer: Text(provider.regionHint),
                ) {
                    TextField("Region", text: $region)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(
                    header: Text("Credentials"),
                    footer: Text("\(provider.keysHint)\n\nThe secret key is stored encrypted and never shown again — most providers only show it once too, when you create the key. Leave it empty when editing to keep the saved one."),
                ) {
                    TextField("Access key", text: $accessKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Secret key", text: $secretKey)
                }

                Section(
                    footer: Text("Puts the bucket in the path (endpoint/bucket) instead of in the hostname. Amazon S3 wants this off; almost everyone else wants it on. The provider above sets it for you."),
                ) {
                    Toggle("Path-style addressing", isOn: $pathStyleAccess)
                }

                if let note = provider.note {
                    Section {
                        Label(note, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
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
