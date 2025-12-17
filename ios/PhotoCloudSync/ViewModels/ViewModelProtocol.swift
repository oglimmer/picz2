import Foundation

// MARK: - ViewModel Protocol

protocol ViewModelProtocol: ObservableObject {
    var isLoading: Bool { get set }
    var alertState: AlertState? { get set }
}

// Extension providing common error handling
extension ViewModelProtocol {
    func handleError(_ error: Error) {
        isLoading = false
        alertState = .error(error)
    }

    func showSuccess(title: String = "Success", message: String) {
        isLoading = false
        alertState = .success(title: title, message: message)
    }
}
