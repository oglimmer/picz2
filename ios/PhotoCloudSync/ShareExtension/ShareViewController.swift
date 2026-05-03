import SafariServices
import Social
import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    // MARK: - State

    private var mediaItems: [MediaItem] = []
    private let uploadService = UploadService.shared
    private var loadedItemCount = 0
    private var totalItemCount = 0
    private var albums: [[String: Any]] = []
    private var selectedAlbumId: Int?
    private var isLoggedIn = false
    private var isUploading = false

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let titleRow = UIView()
    private let titleLabel = UILabel()
    private let accountButton = UIButton(type: .system)
    private let subtitleLabel = UILabel()

    // Login section
    private let loginCard = UIView()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let loginButton = UIButton(type: .system)
    private let loginErrorLabel = UILabel()
    private let registerLink = UILabel()
    private let privacyLink = UILabel()

    // Album section
    private let albumCard = UIView()
    private let albumHeading = UILabel()
    private let albumButton = UIButton(type: .system)

    // Progress
    private let progressView = UIProgressView(progressViewStyle: .default)

    // Bottom bar
    private let bottomBar = UIView()
    private let cancelButton = UIButton(type: .system)
    private let uploadButton = UIButton(type: .system)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        print("🟢 ShareExtension viewDidLoad (build with footer-link rework)")
        view.backgroundColor = .systemGroupedBackground

        setupUI()
        prepareAuthAndLoad()
        loadSharedItems()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Focus the email field only when the user actually has typing to do —
        // not while we're silently re-validating saved credentials, which would
        // pop the keyboard for half a second and then dismiss it.
        let isCheckingAuth = loginButton.configuration?.showsActivityIndicator ?? false
        if !isLoggedIn,
           !loginCard.isHidden,
           (emailField.text ?? "").isEmpty,
           !isCheckingAuth
        {
            emailField.becomeFirstResponder()
        }
    }

    // MARK: - UI setup

    private func setupUI() {
        setupTitleRow()

        subtitleLabel.text = "Preparing media files…"
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true

        setupLoginCard()
        setupAlbumCard()
        setupBottomBar()

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.isHidden = true

        // Content stack
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(titleRow)
        contentStack.addArrangedSubview(subtitleLabel)
        contentStack.setCustomSpacing(24, after: subtitleLabel)
        contentStack.addArrangedSubview(loginCard)
        contentStack.addArrangedSubview(albumCard)
        contentStack.addArrangedSubview(progressView)

        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)
        view.addSubview(bottomBar)

        // Album section starts hidden until login resolves
        albumCard.isHidden = true

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),

            // Bottom bar pinned above keyboard (or above safe area when no keyboard).
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
    }

    private func setupTitleRow() {
        titleLabel.text = "Upload to Photo Cloud"
        titleLabel.font = .preferredFont(forTextStyle: .title2).bolded()
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Account button — hidden until login resolves. Overlays the trailing edge so the
        // title can stay centered without the icon's width pulling it off-axis.
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "person.crop.circle")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        config.contentInsets = .init(top: 4, leading: 4, bottom: 4, trailing: 4)
        accountButton.configuration = config
        accountButton.showsMenuAsPrimaryAction = true
        accountButton.isHidden = true
        accountButton.accessibilityLabel = "Account"
        accountButton.translatesAutoresizingMaskIntoConstraints = false

        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.addSubview(titleLabel)
        titleRow.addSubview(accountButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: titleRow.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: titleRow.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor),

            accountButton.centerYAnchor.constraint(equalTo: titleRow.centerYAnchor),
            accountButton.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor),
        ])
    }

    private func setupLoginCard() {
        styleCard(loginCard)

        emailField.placeholder = "Email"
        emailField.borderStyle = .roundedRect
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.spellCheckingType = .no
        emailField.textContentType = .emailAddress
        emailField.keyboardType = .emailAddress
        emailField.returnKeyType = .next
        emailField.delegate = self
        emailField.addTarget(self, action: #selector(loginFieldChanged), for: .editingChanged)

        passwordField.placeholder = "Password"
        passwordField.borderStyle = .roundedRect
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.returnKeyType = .go
        passwordField.delegate = self
        passwordField.addTarget(self, action: #selector(loginFieldChanged), for: .editingChanged)

        var loginConfig = UIButton.Configuration.filled()
        loginConfig.title = "Sign in"
        loginConfig.buttonSize = .medium
        loginConfig.cornerStyle = .medium
        loginButton.configuration = loginConfig
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        loginButton.isEnabled = false

        loginErrorLabel.text = ""
        loginErrorLabel.textColor = .systemRed
        loginErrorLabel.font = .preferredFont(forTextStyle: .footnote)
        loginErrorLabel.numberOfLines = 0
        loginErrorLabel.adjustsFontForContentSizeCategory = true
        loginErrorLabel.isHidden = true

        let footer = makeLoginFooter()

        let stack = UIStackView(arrangedSubviews: [emailField, passwordField, loginButton, loginErrorLabel, footer])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(16, after: passwordField)
        stack.setCustomSpacing(16, after: loginErrorLabel)
        loginCard.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: loginCard.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: loginCard.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: loginCard.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: loginCard.bottomAnchor, constant: -16),
        ])
    }

    private func makeLoginFooter() -> UIView {
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

    @objc private func registerTapped() {
        guard let url = URL(string: "\(AppConfiguration.baseURL)/register") else { return }
        presentInAppBrowser(url)
    }

    @objc private func privacyTapped() {
        guard let url = URL(string: "\(AppConfiguration.baseURL)/privacy") else { return }
        presentInAppBrowser(url)
    }

    /// SFSafariViewController works inside share extensions where UIApplication.open and
    /// NSExtensionContext.open silently fail. The browser presents modally over our UI so
    /// the user can read the page and come back to finish the upload.
    private func presentInAppBrowser(_ url: URL) {
        let safari = SFSafariViewController(url: url)
        safari.modalPresentationStyle = .pageSheet
        safari.preferredControlTintColor = .tintColor
        present(safari, animated: true)
    }

    private func setupAlbumCard() {
        styleCard(albumCard)

        albumHeading.text = "Destination album"
        albumHeading.font = .preferredFont(forTextStyle: .footnote).bolded()
        albumHeading.textColor = .secondaryLabel
        albumHeading.adjustsFontForContentSizeCategory = true

        var albumConfig = UIButton.Configuration.bordered()
        albumConfig.title = "Loading albums…"
        albumConfig.image = UIImage(systemName: "chevron.up.chevron.down")
        albumConfig.imagePlacement = .trailing
        albumConfig.imagePadding = 8
        albumConfig.cornerStyle = .medium
        albumConfig.titleLineBreakMode = .byTruncatingTail
        // Anchor title to leading edge so the chevron sits flush right.
        albumConfig.titleAlignment = .leading
        albumButton.configuration = albumConfig
        albumButton.contentHorizontalAlignment = .leading
        albumButton.showsMenuAsPrimaryAction = true
        albumButton.changesSelectionAsPrimaryAction = false
        albumButton.isEnabled = false

        let stack = UIStackView(arrangedSubviews: [albumHeading, albumButton])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        albumCard.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: albumCard.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: albumCard.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: albumCard.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: albumCard.bottomAnchor, constant: -16),
        ])
    }

    private func setupBottomBar() {
        bottomBar.backgroundColor = .secondarySystemGroupedBackground
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        // A hairline divider on top.
        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(divider)

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
        bottomBar.addSubview(stack)

        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            stack.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -12),
        ])
    }

    private func styleCard(_ view: UIView) {
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Auth flow

    private func prepareAuthAndLoad() {
        if let creds = CredentialsManager.load() {
            emailField.text = creds.email
            passwordField.text = creds.password
            uploadService.setCredentials(email: creds.email, password: creds.password)
            setLoginBusy(true)
            uploadService.checkAuth { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.setLoginBusy(false)
                    switch result {
                    case let .success(serverEmail):
                        self.didLogIn(email: serverEmail.isEmpty ? creds.email : serverEmail)
                    case .failure:
                        self.isLoggedIn = false
                        self.showLogin()
                    }
                }
            }
        } else {
            showLogin()
        }
    }

    private func showLogin() {
        loginCard.isHidden = false
        albumCard.isHidden = true
        accountButton.isHidden = true
        setLoginError(nil)
        refreshLoginButton()
        refreshUploadButton()
    }

    private func setLoginError(_ message: String?) {
        if let message, !message.isEmpty {
            loginErrorLabel.text = message
            loginErrorLabel.isHidden = false
        } else {
            loginErrorLabel.text = ""
            loginErrorLabel.isHidden = true
        }
    }

    private func didLogIn(email: String) {
        isLoggedIn = true
        view.endEditing(true)
        loginCard.isHidden = true
        albumCard.isHidden = false
        accountButton.isHidden = false
        updateAccountMenu(email: email)
        setAlbumLoading(true)
        loadAlbums()
        refreshUploadButton()
    }

    private func updateAccountMenu(email: String) {
        let signOut = UIAction(
            title: "Sign out",
            image: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmSignOut()
        }
        let header = email.isEmpty ? "Signed in" : "Signed in as \(email)"
        accountButton.menu = UIMenu(title: header, children: [signOut])
    }

    private func confirmSignOut() {
        let alert = UIAlertController(
            title: "Sign out?",
            message: "You'll need to enter your password again the next time you upload.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign out", style: .destructive) { [weak self] _ in
            self?.performSignOut()
        })
        present(alert, animated: true)
    }

    private func performSignOut() {
        CredentialsManager.clear()
        uploadService.clearCredentials()
        isLoggedIn = false
        selectedAlbumId = nil
        albums = []
        emailField.text = ""
        passwordField.text = ""
        progressView.isHidden = true
        progressView.progress = 0
        showLogin()
        emailField.becomeFirstResponder()
    }

    private func setAlbumLoading(_ loading: Bool) {
        var config = albumButton.configuration
        config?.showsActivityIndicator = loading
        if loading { config?.title = "Loading albums…" }
        albumButton.configuration = config
    }

    @objc private func loginFieldChanged() {
        refreshLoginButton()
        if !loginErrorLabel.isHidden { setLoginError(nil) }
    }

    private func refreshLoginButton() {
        let email = emailField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField.text ?? ""
        loginButton.isEnabled = !email.isEmpty && !password.isEmpty
    }

    private func setLoginBusy(_ busy: Bool) {
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

    @objc private func loginTapped() {
        let email = emailField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField.text ?? ""
        setLoginError(nil)
        guard !email.isEmpty, !password.isEmpty else {
            setLoginError("Email and password required")
            return
        }
        view.endEditing(true)
        uploadService.setCredentials(email: email, password: password)
        setLoginBusy(true)
        uploadService.checkAuth { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setLoginBusy(false)
                switch result {
                case let .success(serverEmail):
                    _ = CredentialsManager.save(Credentials(email: email, password: password))
                    self.didLogIn(email: serverEmail.isEmpty ? email : serverEmail)
                case .failure:
                    self.isLoggedIn = false
                    self.setLoginError("Invalid email or password")
                }
            }
        }
    }

    // MARK: - Shared media loading

    private func loadSharedItems() {
        guard let extensionContext,
              let items = extensionContext.inputItems as? [NSExtensionItem]
        else {
            print("❌ No extension context or input items")
            showError("No items to share")
            return
        }

        print("📦 Found \(items.count) extension items")

        totalItemCount = items.reduce(0) { $0 + ($1.attachments?.count ?? 0) }
        loadedItemCount = 0

        print("📎 Total attachments: \(totalItemCount)")

        guard totalItemCount > 0 else {
            print("❌ No attachments found")
            showError("No media items found")
            return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }

            for (index, attachment) in attachments.enumerated() {
                print("🔍 Processing attachment \(index + 1)/\(attachments.count)")
                print("   Registered types: \(attachment.registeredTypeIdentifiers)")

                if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    print("   ✅ Has file URL type - loading...")
                    attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] urlData, error in
                        if let error {
                            print("   ❌ File URL load error: \(error.localizedDescription)")
                        }
                        if let url = urlData as? URL {
                            self?.handleLoadedURL(url: url, error: error)
                        } else if let urlData = urlData as? Data,
                                  let urlString = String(data: urlData, encoding: .utf8),
                                  let url = URL(string: urlString)
                        {
                            self?.handleLoadedURL(url: url, error: nil)
                        } else {
                            self?.loadItemAlternative(attachment: attachment)
                        }
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
                        self?.handleLoadedItem(item: item, error: error, type: .image)
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] item, error in
                        self?.handleLoadedItem(item: item, error: error, type: .video)
                    }
                }
            }
        }
    }

    private func updateMediaSummary() {
        if mediaItems.isEmpty {
            subtitleLabel.text = "No valid media files found"
        } else {
            let imageCount = mediaItems.count(where: { $0.type == .image })
            let videoCount = mediaItems.count(where: { $0.type == .video })
            let parts: String = {
                switch (imageCount, videoCount) {
                case (let i, 0) where i > 0:
                    return "\(i) photo\(i == 1 ? "" : "s")"
                case (0, let v) where v > 0:
                    return "\(v) video\(v == 1 ? "" : "s")"
                default:
                    return "\(imageCount) photo\(imageCount == 1 ? "" : "s"), \(videoCount) video\(videoCount == 1 ? "" : "s")"
                }
            }()
            subtitleLabel.text = "Ready to upload \(parts)"
        }
        refreshUploadButton()
    }

    private func refreshUploadButton() {
        uploadButton.isEnabled = !isUploading
            && isLoggedIn
            && !mediaItems.isEmpty
            && selectedAlbumId != nil
    }

    // MARK: - Upload

    @objc private func uploadTapped() {
        guard !mediaItems.isEmpty else { return }
        guard isLoggedIn else {
            showError("Please sign in first")
            return
        }
        guard let albumId = selectedAlbumId else {
            showError("Select an album to upload to")
            return
        }

        isUploading = true
        refreshUploadButton()
        cancelButton.isEnabled = false
        progressView.isHidden = false
        progressView.progress = 0
        subtitleLabel.text = "Uploading…"

        uploadService.upload(mediaItems: mediaItems, albumId: albumId) { [weak self] progress in
            DispatchQueue.main.async {
                self?.progressView.setProgress(Float(progress), animated: true)
            }
        } completion: { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isUploading = false
                self.cancelButton.isEnabled = true

                switch result {
                case let .success(count):
                    self.subtitleLabel.text = "Uploaded \(count) item\(count == 1 ? "" : "s")"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                    }
                case let .failure(error):
                    self.progressView.isHidden = true
                    self.refreshUploadButton()
                    self.showError("Upload failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func cancelTapped() {
        extensionContext?.cancelRequest(withError: NSError(domain: "PhotoUploader", code: 0, userInfo: [NSLocalizedDescriptionKey: "User cancelled"]))
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITextFieldDelegate

extension ShareViewController: UITextFieldDelegate {
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


// MARK: - Media loading callbacks

extension ShareViewController {
    func loadItemAlternative(attachment: NSItemProvider) {
        if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
                self?.handleLoadedItem(item: item, error: error, type: .image)
            }
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            attachment.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] item, error in
                self?.handleLoadedItem(item: item, error: error, type: .video)
            }
        }
    }

    func handleLoadedURL(url: URL, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            loadedItemCount += 1
            if let error {
                print("❌ Error loading URL: \(error.localizedDescription)")
                if loadedItemCount == totalItemCount { updateMediaSummary() }
                return
            }

            let ext = url.pathExtension.lowercased()
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp"]
            let videoExtensions = ["mov", "mp4", "m4v", "avi", "wmv", "flv", "mkv", "webm"]
            let type: MediaItem.MediaType = if imageExtensions.contains(ext) {
                .image
            } else if videoExtensions.contains(ext) {
                .video
            } else {
                .image
            }
            mediaItems.append(MediaItem(url: url, type: type, filename: url.lastPathComponent))
            if loadedItemCount == totalItemCount { updateMediaSummary() }
        }
    }

    func handleLoadedItem(item: NSSecureCoding?, error: Error?, type: MediaItem.MediaType) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            loadedItemCount += 1
            if let error {
                print("Error loading item: \(error.localizedDescription)")
                if loadedItemCount == totalItemCount { updateMediaSummary() }
                return
            }
            if let url = item as? URL {
                mediaItems.append(MediaItem(url: url, type: type, filename: url.lastPathComponent))
            }
            if loadedItemCount == totalItemCount { updateMediaSummary() }
        }
    }
}

// MARK: - Albums

extension ShareViewController {
    func loadAlbums() {
        let apiUrl = uploadService.getApiBaseUrl()
        guard let url = URL(string: "\(apiUrl)/albums") else {
            print("❌ Invalid albums API URL")
            setAlbumLoading(false)
            albumButton.configuration?.title = "Failed to load albums"
            return
        }

        var request = URLRequest(url: url)
        if let auth = uploadService.getAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setAlbumLoading(false)

                if let error {
                    print("❌ Error loading albums: \(error.localizedDescription)")
                    self.albumButton.configuration?.title = "Failed to load albums"
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (json["success"] as? Bool) == true,
                      let albums = json["albums"] as? [[String: Any]]
                else {
                    self.albumButton.configuration?.title = "Failed to load albums"
                    return
                }

                self.albums = albums
                self.applyAlbumMenu()
                if albums.isEmpty {
                    self.albumButton.configuration?.title = "No albums available"
                    self.albumButton.isEnabled = false
                } else {
                    self.albumButton.isEnabled = true
                    if let first = albums.first, let id = first["id"] as? Int {
                        self.selectAlbum(id: id)
                    }
                }
            }
        }.resume()
    }

    private func applyAlbumMenu() {
        let actions: [UIAction] = albums.compactMap { album in
            guard let id = album["id"] as? Int,
                  let name = album["name"] as? String
            else { return nil }
            let count = album["fileCount"] as? Int ?? 0
            let title = "\(name) (\(count))"
            let isSelected = (id == selectedAlbumId)
            return UIAction(title: title, state: isSelected ? .on : .off) { [weak self] _ in
                self?.selectAlbum(id: id)
            }
        }
        albumButton.menu = UIMenu(title: "Choose album", options: .singleSelection, children: actions)
    }

    private func selectAlbum(id: Int) {
        selectedAlbumId = id
        if let album = albums.first(where: { ($0["id"] as? Int) == id }) {
            let name = (album["name"] as? String) ?? "Album"
            let count = album["fileCount"] as? Int ?? 0
            albumButton.configuration?.title = "\(name) (\(count))"
        }
        applyAlbumMenu()
        refreshUploadButton()
    }
}

// MARK: - Helpers

private extension UIFont {
    func bolded() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
