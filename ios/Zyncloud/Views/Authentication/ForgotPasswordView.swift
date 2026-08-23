import SwiftUI

struct ForgotPasswordView: View {
    @StateObject private var viewModel = ForgotPasswordViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if viewModel.didSubmit {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Check Your Email").font(.headline)
                        Text("If an account exists for \(viewModel.email), you will receive a password reset link shortly.")
                            .font(.callout)
                        Text("The link will expire in 1 hour.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("Back to Login") { dismiss() }
                }
            } else {
                Section(
                    header: Text("Reset Password"),
                    footer: Text("Enter your email address and we'll send you a link to reset your password."),
                ) {
                    TextField("Email", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .textContentType(.username)
                }

                Section {
                    Button(action: viewModel.submit) {
                        HStack {
                            Spacer()
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text("Send Reset Link")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!viewModel.isFormValid || viewModel.isLoading)
                }
            }
        }
        .navigationTitle("Forgot Password")
        .alert(item: $viewModel.alertState) { alertState in
            Alert(title: Text(alertState.title), message: Text(alertState.message))
        }
    }
}
