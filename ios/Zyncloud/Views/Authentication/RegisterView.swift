import SwiftUI

struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    @Environment(\.dismiss) private var dismiss

    private var termsURL: URL? { URL(string: "\(AppConfiguration.baseURL)/terms") }
    private var privacyURL: URL? { URL(string: "\(AppConfiguration.baseURL)/privacy") }

    var body: some View {
        Form {
            if viewModel.didRegister {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Check Your Email").font(.headline)
                        Text("We've sent a confirmation link to \(viewModel.email). Click it to verify your account, then come back here and sign in.")
                            .font(.callout)
                        Text("The link will expire in 24 hours.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("Back to Login") { dismiss() }
                }
            } else {
                Section(header: Text("Account")) {
                    TextField("Email", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .textContentType(.username)

                    SecureField("Password (min 8 chars)", text: $viewModel.password)
                        .textContentType(.newPassword)

                    SecureField("Confirm password", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
                }

                Section(header: Text("Consent")) {
                    Toggle("I accept the Terms and Conditions", isOn: $viewModel.acceptTerms)
                    if let url = termsURL {
                        Link(destination: url) {
                            HStack {
                                Text("Read Terms and Conditions").font(.footnote)
                                Spacer()
                                Image(systemName: "arrow.up.right.square").font(.footnote)
                            }
                        }
                    }

                    Toggle("I accept the Privacy Policy", isOn: $viewModel.acceptPrivacy)
                    if let url = privacyURL {
                        Link(destination: url) {
                            HStack {
                                Text("Read Privacy Policy").font(.footnote)
                                Spacer()
                                Image(systemName: "arrow.up.right.square").font(.footnote)
                            }
                        }
                    }
                }

                Section {
                    Button(action: viewModel.register) {
                        HStack {
                            Spacer()
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text("Create Account")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!viewModel.isFormValid || viewModel.isLoading)
                }
            }
        }
        .navigationTitle("Create Account")
        .alert(item: $viewModel.alertState) { alertState in
            Alert(title: Text(alertState.title), message: Text(alertState.message))
        }
    }
}
