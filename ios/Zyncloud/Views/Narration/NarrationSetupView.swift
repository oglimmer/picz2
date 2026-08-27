import SwiftUI

/// Where an audio commentary starts: pick which photos and which language, then record.
///
/// The album's gallery keys a narration on that pair, so both choices are made here and neither
/// can change once the slideshow is running.
struct NarrationSetupView: View {
    @StateObject private var viewModel: NarrationRecorderViewModel
    @Environment(\.dismiss) private var dismiss

    /// True while the slideshow owns the screen.
    @State private var isSlideshowPresented = false

    /// Set when Record was tapped and a narration for this pair already exists. Recording
    /// anyway leaves the album with two, so it asks first.
    @State private var confirmingOverwrite = false

    /// Set when Delete was tapped on a saved narration, before the confirmation.
    @State private var pendingDelete: RecordingInfo?

    /// The commentary being played back, if any.
    @State private var previewing: RecordingInfo?

    init(album: Album) {
        _viewModel = StateObject(wrappedValue: NarrationRecorderViewModel(album: album))
    }

    var body: some View {
        // Its own navigation container: this arrives as a sheet, which starts with no bar of
        // its own, and the album screen's bar stays behind it.
        NavigationStack {
            content
        }
        .interactiveDismissDisabled(viewModel.phase != .setup)
    }

    private var content: some View {
        List {
            filterSection
            languageSection
            startSection

            if !viewModel.existingRecordings.isEmpty {
                savedSection
            }
        }
        .navigationTitle("Audio Commentary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
                    // Closing mid-upload would take the alert that reports the outcome with it,
                    // and closing on a failed save would throw the audio away with no Retry.
                    .disabled(viewModel.phase != .setup)
            }
        }
        .disabled(viewModel.phase == .saving || viewModel.phase == .saveFailed)
        .overlay {
            if viewModel.phase == .saving {
                savingOverlay
            }
        }
        .fullScreenCover(isPresented: $isSlideshowPresented) {
            NarrationSlideshowView(viewModel: viewModel)
        }
        .fullScreenCover(item: $previewing) { recording in
            NarrationPlaybackView(
                recording: recording,
                photosByID: viewModel.photosByID,
                title: label(for: recording),
            )
        }
        // The slideshow closes itself the moment recording ends, so the upload's outcome —
        // success or failure — is reported here, on the screen the user lands back on.
        .onChange(of: viewModel.phase) { _, phase in
            if phase != .recording {
                isSlideshowPresented = false
            }
        }
        .confirmationDialog(
            "Replace narration",
            isPresented: $confirmingOverwrite,
            titleVisibility: .visible,
        ) {
            Button("Record Anyway") { beginSlideshow() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(overwriteWarning)
        }
        .confirmationDialog(
            "Delete narration",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { shown in
                    if !shown {
                        pendingDelete = nil
                    }
                },
            ),
            titleVisibility: .visible,
            presenting: pendingDelete,
        ) { recording in
            Button("Delete", role: .destructive) {
                pendingDelete = nil
                viewModel.deleteRecording(recording)
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This removes the audio from your server for good. It cannot be undone.")
        }
        .alert(state: $viewModel.alertState)
        .onAppear { viewModel.load() }
    }

    // MARK: - Sections

    private var filterSection: some View {
        Section(
            header: Text("Photos"),
            footer: Text("The commentary is saved against this choice. Pick the same one in the gallery to hear it."),
        ) {
            Picker("Tag filter", selection: $viewModel.selectedTag) {
                Text("All photos (\(viewModel.slidesCountForAllPhotos))").tag(String?.none)
                ForEach(viewModel.availableTags) { tag in
                    Text("\(tag.name) (\(tag.count))").tag(String?.some(tag.name))
                }
            }
            .onChange(of: viewModel.selectedTag) { _, _ in
                viewModel.applyFilter()
            }

            LabeledContent("Slides") {
                Text("\(viewModel.slides.count)")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var languageSection: some View {
        Section(header: Text("Language")) {
            Picker("Language", selection: $viewModel.selectedLanguage) {
                ForEach(NarrationLanguage.allCases) { language in
                    Text(viewModel.name(of: language)).tag(language)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var startSection: some View {
        Section(
            footer: Text(
                "Talk while the slideshow runs. Tap the picture to move on. "
                    + "Videos play without sound so they do not talk over you.",
            ),
        ) {
            Button {
                if viewModel.hasExistingRecordingForSelection {
                    confirmingOverwrite = true
                } else {
                    beginSlideshow()
                }
            } label: {
                Label("Start Recording", systemImage: "mic.circle.fill")
            }
            .disabled(viewModel.slides.isEmpty || viewModel.isLoading)
        }
    }

    /// Only this album's commentaries: the server's list endpoint is scoped to the album *and*
    /// the signed-in user, so nothing another album owns can appear here.
    private var savedSection: some View {
        Section(
            header: Text("Saved For This Album"),
            footer: Text("Preview plays the voice with the photos it was recorded over."),
        ) {
            ForEach(viewModel.existingRecordings) { recording in
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label(for: recording))
                            .font(.body)
                        Text(subtitle(for: recording))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 16) {
                        Button {
                            previewing = recording
                        } label: {
                            Label("Preview", systemImage: "play.circle")
                        }
                        .disabled(recording.audioURL == nil)

                        Button(role: .destructive) {
                            pendingDelete = recording
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    // Rows in a `List` hand every tap to the row itself unless each button
                    // claims its own hit area — without this, Preview and Delete both fire.
                    .buttonStyle(.borderless)
                    .font(.footnote)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("Saving commentary…")
                    .font(.footnote)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Helpers

    /// Built here rather than inline so the dialog body stays one readable line.
    private var overwriteWarning: String {
        let language = viewModel.name(of: viewModel.selectedLanguage)
        return "This album already has a \(language) commentary for \(filterLabel). "
            + "Recording another one leaves both on the server — delete the old one first "
            + "if you want it replaced."
    }

    private func subtitle(for recording: RecordingInfo) -> String {
        let duration = NarrationRecorderViewModel.durationLabel(recording.durationMs ?? 0)
        return "\(recording.filterTag ?? "All photos") · \(duration)"
    }

    private var filterLabel: String {
        viewModel.selectedTag.map { "\"\($0)\"" } ?? "all photos"
    }

    private func label(for recording: RecordingInfo) -> String {
        guard let language = recording.narrationLanguage else {
            return recording.language ?? "Commentary"
        }
        return viewModel.name(of: language)
    }

    private func beginSlideshow() {
        Task {
            await viewModel.startRecording()
            if viewModel.phase == .recording {
                isSlideshowPresented = true
            }
        }
    }
}
