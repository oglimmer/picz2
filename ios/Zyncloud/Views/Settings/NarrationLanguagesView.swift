import SwiftUI

/// The two narration language names, mirroring the web app's "Narration languages" panel.
///
/// Each field saves on commit — return key or focus loss — because these are free-text names, and
/// saving per keystroke would send a request for every letter typed.
struct NarrationLanguagesView: View {
    @StateObject private var viewModel = UserSettingsViewModel()
    @FocusState private var focusedField: Field?

    private enum Field {
        case language1
        case language2
    }

    var body: some View {
        List {
            Section(
                header: Text("Narration Languages"),
                footer: Text("These names label the two narration tracks in your gallery. They are free text, not locale codes — write them the way you want them shown."),
            ) {
                LabeledContent("Language 1") {
                    TextField("e.g. German", text: $viewModel.language1)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .language1)
                        .onSubmit { viewModel.saveLanguage(slot: 1) }
                }

                LabeledContent("Language 2") {
                    TextField("e.g. English", text: $viewModel.language2)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .language2)
                        .onSubmit { viewModel.saveLanguage(slot: 2) }
                }
            }

            if viewModel.isLoading || viewModel.isSavingLanguages {
                Section {
                    HStack {
                        Text(viewModel.isLoading ? "Loading…" : "Saving…")
                            .foregroundColor(.secondary)
                        Spacer()
                        ProgressView()
                    }
                }
            }
        }
        // Leaving a field is a commit, same as the web app's blur handler. Saving only on the
        // return key would silently drop an edit whenever the user tapped the other field.
        .onChange(of: focusedField) { previous, _ in
            switch previous {
            case .language1: viewModel.saveLanguage(slot: 1)
            case .language2: viewModel.saveLanguage(slot: 2)
            case nil: break
            }
        }
        .navigationTitle("Narration Languages")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $viewModel.alertState) { alertState in
            Alert(title: Text(alertState.title), message: Text(alertState.message))
        }
        .onAppear {
            viewModel.loadLanguages()
        }
    }
}
