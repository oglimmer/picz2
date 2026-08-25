import SwiftUI

/// Create, rename and delete the account's tags — the web app's "Manage Tags" panel.
///
/// `no_tag` and `all` come back from the server like any other tag but the gallery depends on
/// them, so they are listed with a badge and neither swipe action nor rename is offered.
struct TagManagerView: View {
    @StateObject private var viewModel = UserSettingsViewModel()
    @State private var newTagName: String = ""
    @State private var editingTagId: Int?
    @State private var editingTagName: String = ""
    @FocusState private var editFieldFocused: Bool

    var body: some View {
        List {
            Section(header: Text("New Tag")) {
                HStack {
                    TextField("Tag name", text: $newTagName)
                        .autocorrectionDisabled()
                        .onSubmit(handleCreate)
                    Button("Add", action: handleCreate)
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || viewModel.isMutatingTag)
                }
            }

            Section(
                header: Text("Tags"),
                footer: Text("Deleting a tag removes it from every photo that carries it. System tags belong to the gallery and cannot be changed."),
            ) {
                if viewModel.isLoadingTags, viewModel.tags.isEmpty {
                    HStack {
                        Text("Loading tags…")
                            .foregroundColor(.secondary)
                        Spacer()
                        ProgressView()
                    }
                } else if viewModel.tags.isEmpty {
                    Text("No tags yet. Add your first one above.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.tags) { tag in
                        row(for: tag)
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
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
                Alert(title: Text(alertState.title), message: Text(alertState.message))
            }
        }
        .onAppear {
            if viewModel.tags.isEmpty {
                viewModel.loadTags()
            }
        }
    }

    @ViewBuilder
    private func row(for tag: Tag) -> some View {
        if editingTagId == tag.id {
            TextField("Tag name", text: $editingTagName)
                .autocorrectionDisabled()
                .focused($editFieldFocused)
                .onSubmit { commitEdit(for: tag) }
        } else {
            HStack {
                Text(tag.name)
                Spacer()
                if tag.isSystem {
                    Text("system")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !tag.isSystem else { return }
                startEdit(tag)
            }
            .swipeActions(edge: .trailing) {
                if !tag.isSystem {
                    Button("Delete", role: .destructive) {
                        viewModel.confirmDeleteTag(tag)
                    }
                    Button("Rename") {
                        startEdit(tag)
                    }
                    .tint(.blue)
                }
            }
        }
    }

    private func handleCreate() {
        let name = newTagName
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.createTag(name: name)
        newTagName = ""
    }

    private func startEdit(_ tag: Tag) {
        editingTagId = tag.id
        editingTagName = tag.name
        editFieldFocused = true
    }

    private func commitEdit(for tag: Tag) {
        viewModel.renameTag(tag, to: editingTagName)
        editingTagId = nil
        editingTagName = ""
    }
}
