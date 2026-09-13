import SwiftUI

struct ChangePasswordView: View {
    @StateObject private var viewModel = ChangePasswordViewModel()
    @Environment(\.dismiss) private var dismiss
    @Binding var isLoggedIn: Bool

    var body: some View {
        Form {
            if viewModel.didChange {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password Changed").font(.headline)
                        Text("This phone now uses the new password.")
                            .font(.callout)
                        Text("Your other devices and browsers are signed out. Sign in there again with the new password.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("Done") { dismiss() }
                }
            } else if viewModel.mustSignInAgain {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password Changed").font(.headline)
                        Text("This phone could not save the new password. Please sign in again with the new password.")
                            .font(.callout)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("Sign In Again") { isLoggedIn = false }
                }
            } else {
                Section(header: Text("Current Password")) {
                    SecureField("Current password", text: $viewModel.currentPassword)
                        .textContentType(.password)
                }

                Section(
                    header: Text("New Password"),
                    footer: Text(viewModel.validationHint
                        ?? "At least \(ChangePasswordViewModel.minimumLength) characters."),
                ) {
                    SecureField("New password", text: $viewModel.newPassword)
                        .textContentType(.newPassword)
                    SecureField("Confirm new password", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
                }

                Section {
                    Button(action: viewModel.submit) {
                        HStack {
                            Spacer()
                            if viewModel.isLoading {
                                ProgressView()
                            } else {
                                Text("Change Password")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!viewModel.isFormValid || viewModel.isLoading)
                }
            }
        }
        .navigationTitle("Change Password")
        .navigationBarBackButtonHidden(viewModel.mustSignInAgain)
        .alert(state: $viewModel.alertState)
    }
}
