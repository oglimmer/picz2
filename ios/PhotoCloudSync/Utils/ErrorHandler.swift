import Foundation

// MARK: - App Errors

enum AppError: LocalizedError {
    case network(Error)
    case api(message: String, statusCode: Int?)
    case authentication(String)
    case photoLibrary(String)
    case storage(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case let .network(error):
            return "Network error: \(error.localizedDescription)"
        case let .api(message, statusCode):
            if let code = statusCode {
                return "API error (\(code)): \(message)"
            }
            return "API error: \(message)"
        case let .authentication(message):
            return "Authentication error: \(message)"
        case let .photoLibrary(message):
            return "Photo library error: \(message)"
        case let .storage(message):
            return "Storage error: \(message)"
        case let .unknown(error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Alert State

struct AlertState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let primaryButton: AlertButton?
    let secondaryButton: AlertButton?

    struct AlertButton {
        let title: String
        let action: () -> Void
    }

    init(title: String, message: String, primaryButton: AlertButton? = nil, secondaryButton: AlertButton? = nil) {
        self.title = title
        self.message = message
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
    }

    static func error(_ error: Error) -> AlertState {
        let appError = error as? AppError ?? .unknown(error)
        return AlertState(
            title: "Error",
            message: appError.errorDescription ?? "An unknown error occurred",
        )
    }

    static func success(title: String = "Success", message: String) -> AlertState {
        AlertState(title: title, message: message)
    }

    static func confirmation(
        title: String,
        message: String,
        confirmTitle: String = "Confirm",
        confirmAction: @escaping () -> Void,
        cancelTitle: String = "Cancel",
    ) -> AlertState {
        AlertState(
            title: title,
            message: message,
            primaryButton: AlertButton(title: confirmTitle, action: confirmAction),
            secondaryButton: AlertButton(title: cancelTitle, action: {}),
        )
    }
}
