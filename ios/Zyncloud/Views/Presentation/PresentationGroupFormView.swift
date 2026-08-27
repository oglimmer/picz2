import SwiftUI

/// Writing a chapter: its heading, and optionally a paragraph under it.
///
/// A chapter is an anchor on one photo — it starts there and runs until the next one begins — so
/// neither the tag nor the anchor is editable here. Moving a chapter is removing it and starting
/// a new one, which is also how the web app and the server treat it.
struct PresentationGroupFormView: View {
    /// What is being written.
    enum Target: Identifiable {
        /// A new chapter, anchored at this photo.
        case new(anchor: Photo)

        case existing(PresentationGroup)

        var id: String {
            switch self {
            case let .new(anchor): "new-\(anchor.id)"
            case let .existing(group): "group-\(group.id)"
            }
        }
    }

    let target: Target

    /// The tag this chapter belongs to, shown so it is clear which reading of the album is being
    /// written — a chapter placed under one tag is invisible under every other.
    let tag: String

    @ObservedObject var viewModel: PresentationViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var label: String
    @State private var text: String

    /// Set when the draft was refused before it was ever sent — a missing or over-long field.
    /// A refusal from the server arrives through the view model's alert, presented below.
    @State private var problem: PresentationGroupDraft.Problem?

    @FocusState private var labelFocused: Bool

    init(target: Target, tag: String, viewModel: PresentationViewModel) {
        self.target = target
        self.tag = tag
        self.viewModel = viewModel

        switch target {
        case .new:
            _label = State(initialValue: "")
            _text = State(initialValue: "")
        case let .existing(group):
            _label = State(initialValue: group.label)
            _text = State(initialValue: group.text ?? "")
        }
    }

    private var isEditing: Bool {
        if case .existing = target { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Arrival", text: $label)
                        .focused($labelFocused)
                } header: {
                    Text("Label")
                } footer: {
                    if let problem {
                        Text(problem.message)
                            .foregroundColor(.red)
                    } else if !isEditing {
                        Text("The chapter starts at this photo and runs until the next one begins.")
                    }
                }

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                } header: {
                    Text("Text")
                } footer: {
                    Text("Optional. A sentence or two about this part of the album.")
                }

                Section {
                    LabeledContent("Tag") {
                        Text(tag)
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("A chapter belongs to one tag. It is only shown when the album is read under \"\(tag)\".")
                }
            }
            .navigationTitle(isEditing ? "Edit Chapter" : "New Chapter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isSavingGroup)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Create") { save() }
                        .disabled(
                            viewModel.isSavingGroup
                                || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        )
                }
            }
            .disabled(viewModel.isSavingGroup)
            .overlay {
                if viewModel.isSavingGroup {
                    savingOverlay
                }
            }
            .onAppear {
                // A new chapter opens with an empty label and nothing else to do first.
                if !isEditing {
                    labelFocused = true
                }
            }
        }
        // The screen behind carries this same alert, but an alert presented behind a sheet never
        // reaches anyone — so a refused save has to be able to say so from up here, where the
        // words that were refused still are.
        .alert(state: $viewModel.alertState)
        // Closing mid-save would take the form away while the request is still deciding whether
        // it worked.
        .interactiveDismissDisabled(viewModel.isSavingGroup)
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            ProgressView("Saving…")
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// Checks the draft by the server's own rules before spending a round trip on it, then keeps
    /// the sheet open if the server refuses anyway — the words are still in the fields, and
    /// throwing them away on a failure is the one thing a form must not do.
    private func save() {
        switch PresentationGroupDraft.make(label: label, text: text) {
        case let .failure(problem):
            self.problem = problem

        case let .success(draft):
            problem = nil
            Task {
                let saved: Bool
                switch target {
                case let .new(anchor):
                    saved = await viewModel.createGroup(startingAt: anchor, draft: draft)
                case let .existing(group):
                    saved = await viewModel.updateGroup(group, draft: draft)
                }

                if saved {
                    dismiss()
                }
            }
        }
    }
}
