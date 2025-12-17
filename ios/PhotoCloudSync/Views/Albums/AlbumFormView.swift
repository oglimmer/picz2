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
    let onSave: (String, String?) -> Void

    @State private var name: String
    @State private var description: String

    @Environment(\.dismiss) private var dismiss

    init(mode: Mode, onSave: @escaping (String, String?) -> Void) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _description = State(initialValue: "")
        case let .edit(album):
            _name = State(initialValue: album.name)
            _description = State(initialValue: album.description ?? "")
        }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Album Details")) {
                    TextField("Name", text: $name)
                        .autocapitalization(.words)

                    if #available(iOS 16.0, *) {
                        TextField("Description (optional)", text: $description, axis: .vertical)
                            .lineLimit(3 ... 6)
                    } else {
                        // iOS 15 fallback
                        TextField("Description (optional)", text: $description)
                            .lineLimit(3)
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
        }
    }

    private func handleSave() {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(
            name.trimmingCharacters(in: .whitespacesAndNewlines),
            trimmedDescription.isEmpty ? nil : trimmedDescription,
        )
    }
}
