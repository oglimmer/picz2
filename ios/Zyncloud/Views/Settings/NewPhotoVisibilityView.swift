import SwiftUI

/// Which tag new uploads get, mirroring the web app's "New Photo Visibility" panel (D70).
///
/// Written as two tappable rows rather than a `Picker`, because each option needs a paragraph
/// explaining what it does to a shared album — a picker gives a label and nothing else, and the
/// consequence of the second option is the whole point of the screen.
///
/// The rows read straight off the view model, so a cancelled confirmation or a failed save leaves
/// the old option ticked with no roll-back code.
struct NewPhotoVisibilityView: View {
    @StateObject private var viewModel = UserSettingsViewModel()

    var body: some View {
        List {
            Section(
                header: Text("New Photo Visibility"),
                footer: Text("Every photo and video you upload is tagged automatically. This is the tag it gets. Public visitors of a shared album never see anything tagged \"hidden\"."),
            ) {
                ForEach(NewAssetTag.allCases) { option in
                    Button {
                        viewModel.selectNewAssetTag(option)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: viewModel.newAssetTag == option ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(viewModel.newAssetTag == option ? .accentColor : .secondary)
                                .imageScale(.large)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(option.title)
                                        .foregroundColor(.primary)

                                    if option == .hidden {
                                        Text("RECOMMENDED")
                                            .font(.caption2.weight(.bold))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Text(option.explanation)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .disabled(viewModel.isLoadingNewAssetTag || viewModel.isSavingNewAssetTag)
                }
            }

            Section {
                Text("Changing this only affects photos uploaded from now on. Nothing already in your albums is re-tagged either way.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if viewModel.isLoadingNewAssetTag || viewModel.isSavingNewAssetTag {
                Section {
                    HStack {
                        Text(viewModel.isLoadingNewAssetTag ? "Loading…" : "Saving…")
                            .foregroundColor(.secondary)
                        Spacer()
                        ProgressView()
                    }
                }
            }
        }
        .navigationTitle("New Photos")
        .navigationBarTitleDisplayMode(.inline)
        .alert(state: $viewModel.alertState)
        .onAppear {
            viewModel.loadNewAssetTag()
        }
    }
}
