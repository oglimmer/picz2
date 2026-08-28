import UIKit

// MARK: - Shared styling

extension UIFont {
    func bolded() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

/// Rounded "inset grouped" card — the visual container for the login and album sections.
class ShareCardView: UIView {
    init() {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - Title row

/// The centered sheet title with the account button overlaid on the trailing edge, so the
/// icon's width never pulls the title off-axis.
final class TitleRowView: UIView {
    private let titleLabel = UILabel()
    private let accountButton = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "Upload to Photo Cloud"
        titleLabel.font = .preferredFont(forTextStyle: .title2).bolded()
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Account button — hidden until login resolves.
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "person.crop.circle")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        config.contentInsets = .init(top: 4, leading: 4, bottom: 4, trailing: 4)
        accountButton.configuration = config
        accountButton.showsMenuAsPrimaryAction = true
        accountButton.isHidden = true
        accountButton.accessibilityLabel = "Account"
        accountButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(accountButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            accountButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            accountButton.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows the account button with the given menu, or hides it when `menu` is nil —
    /// the button only appears while someone is signed in.
    func setAccountMenu(_ menu: UIMenu?) {
        accountButton.menu = menu
        accountButton.isHidden = (menu == nil)
    }
}

// MARK: - Login card

/// The sign-in form: email + password fields, the sign-in button, an inline error line, and
/// the create-account / privacy footer links. Owns all field behavior (return-key routing,
/// enablement, busy state); the controller only hears about completed submissions.
final class LoginCardView: ShareCardView {
    /// Fired with a trimmed email and the password when the user submits the form.
    var onSubmit: ((_ email: String, _ password: String) -> Void)?
    var onRegister: (() -> Void)?
    var onPrivacy: (() -> Void)?

    /// Whether a sign-in attempt is in flight. The controller consults this before
    /// auto-focusing the email field, so the keyboard doesn't pop during a silent
    /// re-validation of saved credentials.
    private(set) var isBusy = false

    var isEmailEmpty: Bool { (emailField.text ?? "").isEmpty }

    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let loginButton = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let registerLink = UILabel()
    private let privacyLink = UILabel()

    override init() {
        super.init()

        emailField.placeholder = "Email"
        emailField.borderStyle = .roundedRect
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.spellCheckingType = .no
        emailField.textContentType = .emailAddress
        emailField.keyboardType = .emailAddress
        emailField.returnKeyType = .next
        emailField.delegate = self
        emailField.addTarget(self, action: #selector(fieldChanged), for: .editingChanged)

        passwordField.placeholder = "Password"
        passwordField.borderStyle = .roundedRect
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.returnKeyType = .go
        passwordField.delegate = self
        passwordField.addTarget(self, action: #selector(fieldChanged), for: .editingChanged)

        var loginConfig = UIButton.Configuration.filled()
        loginConfig.title = "Sign in"
        loginConfig.buttonSize = .medium
        loginConfig.cornerStyle = .medium
        loginButton.configuration = loginConfig
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        loginButton.isEnabled = false

        errorLabel.text = ""
        errorLabel.textColor = .systemRed
        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.numberOfLines = 0
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.isHidden = true

        let footer = makeFooter()

        let stack = UIStackView(arrangedSubviews: [emailField, passwordField, loginButton, errorLabel, footer])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(16, after: passwordField)
        stack.setCustomSpacing(16, after: errorLabel)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    // MARK: Controller-facing API

    func prefill(email: String, password: String) {
        emailField.text = email
        passwordField.text = password
        refreshLoginButton()
    }

    func clearFields() {
        emailField.text = ""
        passwordField.text = ""
        refreshLoginButton()
    }

    func focusEmail() {
        emailField.becomeFirstResponder()
    }

    func setBusy(_ busy: Bool) {
        isBusy = busy
        emailField.isEnabled = !busy
        passwordField.isEnabled = !busy
        var config = loginButton.configuration
        config?.showsActivityIndicator = busy
        config?.title = busy ? "Signing in…" : "Sign in"
        loginButton.configuration = config
        loginButton.isEnabled = !busy
            && !(emailField.text?.isEmpty ?? true)
            && !(passwordField.text?.isEmpty ?? true)
    }

    func setError(_ message: String?) {
        if let message, !message.isEmpty {
            errorLabel.text = message
            errorLabel.isHidden = false
        } else {
            errorLabel.text = ""
            errorLabel.isHidden = true
        }
    }

    // MARK: Internals

    private func makeFooter() -> UIView {
        configureLink(registerLink, title: "Create account", action: #selector(registerTapped))
        configureLink(privacyLink, title: "Privacy", action: #selector(privacyTapped))

        let dot = UILabel()
        dot.text = "·"
        dot.textColor = .tertiaryLabel
        dot.font = .preferredFont(forTextStyle: .footnote)
        dot.adjustsFontForContentSizeCategory = true

        let row = UIStackView(arrangedSubviews: [registerLink, dot, privacyLink])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])
        return container
    }

    private func configureLink(_ label: UILabel, title: String, action: Selector) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .footnote),
            .foregroundColor: UIColor.tintColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        label.attributedText = NSAttributedString(string: title, attributes: attrs)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.isUserInteractionEnabled = true
        // Apple's minimum recommended tap target — the visible text is small but the
        // hit area extends vertically.
        label.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        let tap = UITapGestureRecognizer(target: self, action: action)
        label.addGestureRecognizer(tap)
    }

    @objc private func fieldChanged() {
        refreshLoginButton()
        if !errorLabel.isHidden { setError(nil) }
    }

    private func refreshLoginButton() {
        let email = emailField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField.text ?? ""
        loginButton.isEnabled = !email.isEmpty && !password.isEmpty
    }

    @objc private func loginTapped() {
        let email = emailField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField.text ?? ""
        setError(nil)
        guard !email.isEmpty, !password.isEmpty else {
            setError("Email and password required")
            return
        }
        endEditing(true)
        onSubmit?(email, password)
    }

    @objc private func registerTapped() { onRegister?() }
    @objc private func privacyTapped() { onPrivacy?() }
}

extension LoginCardView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === emailField {
            passwordField.becomeFirstResponder()
        } else if textField === passwordField {
            textField.resignFirstResponder()
            if loginButton.isEnabled { loginTapped() }
        }
        return true
    }
}

// MARK: - Album card

/// The destination-album picker: a heading and a pull-down button whose menu the
/// controller supplies.
final class AlbumCardView: ShareCardView {
    private let heading = UILabel()
    private let albumButton = UIButton(type: .system)

    var isPickerEnabled: Bool {
        get { albumButton.isEnabled }
        set { albumButton.isEnabled = newValue }
    }

    override init() {
        super.init()

        heading.text = "Destination album"
        heading.font = .preferredFont(forTextStyle: .footnote).bolded()
        heading.textColor = .secondaryLabel
        heading.adjustsFontForContentSizeCategory = true

        var config = UIButton.Configuration.bordered()
        config.title = "Loading albums…"
        config.image = UIImage(systemName: "chevron.up.chevron.down")
        config.imagePlacement = .trailing
        config.imagePadding = 8
        config.cornerStyle = .medium
        config.titleLineBreakMode = .byTruncatingTail
        // Anchor title to leading edge so the chevron sits flush right.
        config.titleAlignment = .leading
        albumButton.configuration = config
        albumButton.contentHorizontalAlignment = .leading
        albumButton.showsMenuAsPrimaryAction = true
        albumButton.changesSelectionAsPrimaryAction = false
        albumButton.isEnabled = false

        let stack = UIStackView(arrangedSubviews: [heading, albumButton])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    func setLoading(_ loading: Bool) {
        var config = albumButton.configuration
        config?.showsActivityIndicator = loading
        if loading { config?.title = "Loading albums…" }
        albumButton.configuration = config
    }

    func setTitle(_ title: String) {
        albumButton.configuration?.title = title
    }

    func setMenu(_ menu: UIMenu) {
        albumButton.menu = menu
    }
}

// MARK: - Bottom bar

/// The Cancel / Upload bar pinned above the keyboard, with a hairline divider on top.
final class ShareBottomBar: UIView {
    var onCancel: (() -> Void)?
    var onUpload: (() -> Void)?

    var isUploadEnabled: Bool {
        get { uploadButton.isEnabled }
        set { uploadButton.isEnabled = newValue }
    }

    var isCancelEnabled: Bool {
        get { cancelButton.isEnabled }
        set { cancelButton.isEnabled = newValue }
    }

    private let cancelButton = UIButton(type: .system)
    private let uploadButton = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemGroupedBackground
        translatesAutoresizingMaskIntoConstraints = false

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        var cancelConfig = UIButton.Configuration.plain()
        cancelConfig.title = "Cancel"
        cancelConfig.buttonSize = .medium
        cancelButton.configuration = cancelConfig
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        var uploadConfig = UIButton.Configuration.filled()
        uploadConfig.title = "Upload"
        uploadConfig.image = UIImage(systemName: "arrow.up.circle.fill")
        uploadConfig.imagePadding = 6
        uploadConfig.buttonSize = .medium
        uploadConfig.cornerStyle = .medium
        uploadButton.configuration = uploadConfig
        uploadButton.addTarget(self, action: #selector(uploadTapped), for: .touchUpInside)
        uploadButton.isEnabled = false

        let stack = UIStackView(arrangedSubviews: [cancelButton, UIView(), uploadButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func cancelTapped() { onCancel?() }
    @objc private func uploadTapped() { onUpload?() }
}
