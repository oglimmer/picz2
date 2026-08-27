import Foundation
import SwiftUI

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
        /// How the button is drawn. Carried here rather than chosen by the screen, because the
        /// screen does not know which of the two buttons is the dangerous one — five views used
        /// to guess, and three guessed differently. `.destructive` is red; `.cancel` is the
        /// bold dismiss; nil is an ordinary button.
        let role: ButtonRole?
        let action: () -> Void

        init(title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
            self.title = title
            self.role = role
            self.action = action
        }
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
            primaryButton: AlertButton(title: confirmTitle, role: .destructive, action: confirmAction),
            secondaryButton: AlertButton(title: cancelTitle, role: .cancel, action: {}),
        )
    }
}

// MARK: - Presenting an AlertState

extension View {
    /// Presents an ``AlertState`` when one is set, and clears it when the alert is dismissed.
    ///
    /// Eleven screens each open-coded this against `.alert(item:)` and the `Alert` value type,
    /// both deprecated since iOS 15. They also disagreed about which button was the dangerous
    /// one — the same confirm button was red on one screen and blue on another, and the
    /// Retry/Discard alert reddened Retry. Roles now travel on ``AlertState/AlertButton``,
    /// where the code that knows what the button does can set them, and this renders them.
    ///
    /// With no buttons in the state, the actions builder stays empty and SwiftUI supplies its
    /// own "OK" — the same thing `Alert(title:message:)` used to do.
    func alert(state: Binding<AlertState?>) -> some View {
        alert(
            state.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { state.wrappedValue != nil },
                set: { presented in if !presented { state.wrappedValue = nil } },
            ),
            presenting: state.wrappedValue,
        ) { presented in
            if let primary = presented.primaryButton, let secondary = presented.secondaryButton {
                Button(primary.title, role: primary.role, action: primary.action)
                Button(secondary.title, role: secondary.role, action: secondary.action)
            }
        } message: { presented in
            Text(presented.message)
        }
    }
}
