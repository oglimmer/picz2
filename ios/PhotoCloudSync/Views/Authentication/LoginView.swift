import SwiftUI

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        Form {
            Section(header: Text("Sign In")) {
                TextField("Email", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textContentType(.username)

                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
            }

            Section {
                Button(action: handleLogin) {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Sign In")
                        }
                        Spacer()
                    }
                }
                .disabled(!viewModel.isFormValid || viewModel.isLoading)
            }

            Section {
                NavigationLink {
                    ForgotPasswordView()
                } label: {
                    Text("Forgot password?")
                }

                NavigationLink {
                    RegisterView()
                } label: {
                    Text("Create account")
                }
            }
        }
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $viewModel.alertState) { alertState in
            if let primaryButton = alertState.primaryButton,
               let secondaryButton = alertState.secondaryButton
            {
                Alert(
                    title: Text(alertState.title),
                    message: Text(alertState.message),
                    primaryButton: .default(Text(primaryButton.title), action: primaryButton.action),
                    secondaryButton: .cancel(Text(secondaryButton.title), action: secondaryButton.action),
                )
            } else {
                Alert(
                    title: Text(alertState.title),
                    message: Text(alertState.message),
                )
            }
        }
    }

    private func handleLogin() {
        viewModel.login { success in
            if success {
                isLoggedIn = true
            }
        }
    }
}
