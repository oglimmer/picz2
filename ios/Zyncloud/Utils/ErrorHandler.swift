import Foundation

// ``AppError`` used to live here. It moved to `Shared/AppError.swift` so the share extension,
// which cannot see `Utils/`, reports failures as the same type the app does.

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
