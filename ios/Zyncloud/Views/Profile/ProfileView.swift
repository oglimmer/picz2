import SwiftUI

/// The account: who is signed in, the password, the account-wide photo settings, sign-out and
/// delete. Mirrors the web app's Profile page; the Options tab keeps what belongs to this phone.
struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    /// Observed directly, not through the view model, so the switch re-renders (§5.5).
    @ObservedObject private var settings = Settings.shared
    @Binding var isLoggedIn: Bool

    /// The web app's home-server guide, in a sheet like on the sign-up form.
    @State private var showsHomeServerGuide = false

    /// Step 1 of the account delete — the "are you sure" sheet.
    @State private var showDeleteAccountConfirm = false
    /// Step 2 — set only once step 1 was confirmed, which swaps the row for a final warning.
    ///
    /// The web app stacks two modal confirms here. On iOS the second one cannot be a second
    /// `.alert`: this view already carries `.alert(state:)` for `alertState`, and two alert
    /// modifiers on one view fight over the same presentation slot — the later one silently
    /// wins. So the final warning is an inline armed state instead. Same two deliberate
    /// destructive taps, one presenter.
    @State private var deleteAccountArmed = false

    var body: some View {
        List {
            Section(header: Text("Account")) {
                LabeledContent("Email", value: viewModel.email)

                NavigationLink("Change Password") {
                    ChangePasswordView(isLoggedIn: $isLoggedIn)
                }
            }

            // These live on the user, not on this device, so they are the same values the web
            // app edits on its Profile page.
            Section(
                header: Text("Photos"),
                footer: Text("The guide shows how to keep an album's photos on a server in your own home."),
            ) {
                NavigationLink("New Photo Visibility") {
                    NewPhotoVisibilityView()
                }

                NavigationLink("Photo Storage") {
                    StorageBackendsView()
                }

                Button {
                    showsHomeServerGuide = true
                } label: {
                    HStack {
                        Text("Home-Server Guide")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(footer: Text("Shows the Status tab with the upload log and sync details. For this phone only.")) {
                Toggle("Debug Information", isOn: $settings.showsDebugInformation)
            }

            Section {
                Button("Logout") {
                    viewModel.logout {
                        isLoggedIn = false
                    }
                }
                .foregroundColor(.red)
            }

            Section(
                header: Text("Danger Zone"),
                footer: Text("Deleting your account removes your albums, photos, tags and settings from the server for good. There is no undo and no export afterwards."),
            ) {
                if viewModel.isDeletingAccount {
                    HStack {
                        Text("Deleting account…")
                            .foregroundColor(.secondary)
                        Spacer()
                        ProgressView()
                    }
                } else if deleteAccountArmed {
                    Text("Final warning — this cannot be undone.")
                        .font(.footnote)
                        .foregroundColor(.red)

                    Button("Yes, Delete Everything") {
                        deleteAccountArmed = false
                        viewModel.deleteAccount {
                            isLoggedIn = false
                        }
                    }
                    .foregroundColor(.red)

                    Button("Cancel") {
                        deleteAccountArmed = false
                    }
                } else {
                    Button("Delete Account") {
                        showDeleteAccountConfirm = true
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Profile")
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible,
        ) {
            Button("Delete My Account", role: .destructive) {
                deleteAccountArmed = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all your albums, all your photos, all your tags and all your settings. This action cannot be undone.")
        }
        .alert(state: $viewModel.alertState)
        .sheet(isPresented: $showsHomeServerGuide) {
            LegalPageSheet(url: AppConfiguration.homeServerGuideURL).ignoresSafeArea()
        }
    }
}
