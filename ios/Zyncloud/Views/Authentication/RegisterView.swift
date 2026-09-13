import SwiftUI

struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    @Environment(\.dismiss) private var dismiss
    /// The home-server guide, shown in the app like the legal pages rather than sending the
    /// reader out to Safari halfway through the sign-up.
    @State private var showsHomeServerGuide = false

    private var termsURL: URL? {
        LegalPage.terms.url
    }

    private var privacyURL: URL? {
        LegalPage.privacy.url
    }

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

                Section(
                    header: Text("Your Photos, at Home"),
                    footer: Text("Picz can keep an album's photo files on a server in your own home instead of on this site — private, and independent of any cloud company. The guide shows how to set one up. You can do it any time after you sign up."),
                ) {
                    Button {
                        showsHomeServerGuide = true
                    } label: {
                        HStack {
                            Label("Read the home-server guide", systemImage: "house")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
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
        .alert(state: $viewModel.alertState)
        .sheet(isPresented: $showsHomeServerGuide) {
            LegalPageSheet(url: AppConfiguration.homeServerGuideURL).ignoresSafeArea()
        }
    }
}
