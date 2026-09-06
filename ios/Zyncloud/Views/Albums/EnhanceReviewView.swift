import Combine
import SwiftUI

/// Original against enhanced, as large as the screen allows, with Keep and Use underneath (D82).
///
/// The two pictures are stacked and one is visible at a time — a crossfade or a split view would
/// make a small change harder to see, not easier. The segmented control picks the side; pressing
/// and holding the picture peeks at the original from either.
struct EnhanceReviewView: View {
    @ObservedObject var session: EnhanceReviewSession
    let viewModel: AlbumDetailViewModel
    /// Called once with the accepted ids when the review ends, before the cover dismisses.
    let onFinished: ([Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var peeking = false

    private var showsEnhanced: Bool {
        session.preview != nil && session.showsEnhanced && !peeking
    }

    private var title: String {
        session.count > 1 ? "Enhance \(session.index + 1) of \(session.count)" : "Enhance"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let photo = session.current {
                    stage(for: photo)
                }
            }
            .safeAreaInset(edge: .bottom) {
                controls
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        session.cancel()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            session.start()
        }
        .onReceive(session.$isFinished) { finished in
            guard finished else { return }
            onFinished(session.acceptedIds)
            dismiss()
        }
    }

    @ViewBuilder
    private func stage(for photo: Photo) -> some View {
        ZStack {
            if let url = viewModel.fullImageURL(for: photo) {
                AuthenticatedImage(url: url)
                    .scaledToFit()
                    .opacity(showsEnhanced ? 0 : 1)
            }
            if let preview = session.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .opacity(showsEnhanced ? 1 : 0)
            }
            if session.isLoading {
                statusPill(isError: false) {
                    ProgressView().tint(.white)
                    Text("Building the enhanced version…")
                }
            } else if let message = session.errorMessage {
                statusPill(isError: true) {
                    Text(message)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if session.preview != nil {
                Text(showsEnhanced ? "ENHANCED" : "ORIGINAL")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(12)
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            if session.preview != nil {
                peeking = pressing
            }
        }, perform: {})
    }

    private func statusPill(isError: Bool, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isError ? Color.red.opacity(0.85) : Color.black.opacity(0.55), in: Capsule())
        .padding()
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Compare", selection: $session.showsEnhanced) {
                Text("Original").tag(false)
                Text("Enhanced").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(session.preview == nil)

            Text("Press and hold the picture to see the original.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(session.errorMessage == nil ? "Keep Original" : "Skip") {
                    session.decline()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Use Enhanced") {
                    session.accept()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(session.preview == nil || session.isLoading)
            }
            .controlSize(.large)
        }
        .padding()
        .background(Color.black)
    }
}
