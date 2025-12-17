import SwiftUI

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Authentication")) {
                    TextField("Username", text: $viewModel.username)
                        .autocapitalization(.none)
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
                                Text("Login")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!viewModel.isFormValid || viewModel.isLoading)
                }
            }
            .navigationTitle("Login")
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
    }

    private func handleLogin() {
        viewModel.login { success in
            if success {
                isLoggedIn = true
            }
        }
    }
}
