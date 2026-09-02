import SwiftUI

/// Writes the owner's caption for one photo (D69).
///
/// Its own sheet rather than an inline field: a caption is a sentence or two, and a text box
/// inside a grid cell or over a full-screen picture would be typed into blind behind the
/// keyboard. Saving an empty box clears the caption — there is no separate Remove button,
/// because "delete the text and save" is what everyone tries first anyway.
struct PhotoCaptionView: View {
    let photo: Photo

    @ObservedObject var viewModel: AlbumDetailViewModel

    @Environment(\.dismiss) private var dismiss

    /// Mirrors MAX_CAPTION_LENGTH in the server's FileStorageService. Enforced while typing so
    /// nobody writes a paragraph and loses it to a rejected save.
    private static let maxLength = 2000

    /// The photo as the view model holds it now, so a save made from elsewhere is not undone by
    /// a stale copy captured when the sheet opened.
    private var current: Photo {
        viewModel.photos.first { $0.id == photo.id } ?? photo
    }

    @State private var draft: String = ""

    /// Set once in `onAppear`. Without it, every body re-evaluation would re-seed `draft` from
    /// the server's copy and wipe what is being typed.
    @State private var didSeedDraft = false

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft)
                        .frame(minHeight: 140)
                        .focused($isFocused)
                        .onChange(of: draft) { _, new in
                            if new.count > Self.maxLength {
                                draft = String(new.prefix(Self.maxLength))
                            }
                        }
                } header: {
                    Text("Caption")
                } footer: {
                    Text("Anyone with the album's share link can read this, under the photo and on the photo itself.")
                }
            }
            .navigationTitle("Caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        viewModel.updateCaption(
                            draft.trimmingCharacters(in: .whitespacesAndNewlines),
                            on: current,
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !didSeedDraft else { return }
                draft = current.caption ?? ""
                didSeedDraft = true
                isFocused = true
            }
        }
    }
}
