import SafariServices
import Social
import UIKit
import os

/// The share sheet's coordinator. The section views live in `ShareSheetViews.swift`,
/// attachment loading in `SharedItemsLoader`, and the albums request in
/// `ShareAlbumsLoader` — what remains here is layout assembly, the auth flow, and the
/// upload itself.
class ShareViewController: UIViewController {
    // MARK: - State

    private var mediaItems: [MediaItem] = []
    private var skippedCount = 0
    private let uploadService = UploadService.shared
    private let itemsLoader = SharedItemsLoader()
    private var albums: [ShareAlbum] = []
    private var selectedAlbumId: Int?
    private var isLoggedIn = false
    private var isUploading = false

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleRow = TitleRowView()
    private let subtitleLabel = UILabel()
    private let loginCard = LoginCardView()
    private let albumCard = AlbumCardView()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let bottomBar = ShareBottomBar()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        AppLog.share.info("Share sheet opened")
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
        if !isLoggedIn, !loginCard.isHidden, loginCard.isEmailEmpty, !loginCard.isBusy {
            loginCard.focusEmail()
        }
    }

    // MARK: - Layout

    private func setupUI() {
        subtitleLabel.text = "Preparing media files…"
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true

        loginCard.onSubmit = { [weak self] email, password in
            self?.logIn(email: email, password: password)
        }
        loginCard.onRegister = { [weak self] in self?.openInAppBrowser(path: "/register") }
        loginCard.onPrivacy = { [weak self] in self?.openInAppBrowser(path: "/privacy") }

        bottomBar.onCancel = { [weak self] in self?.cancelTapped() }
        bottomBar.onUpload = { [weak self] in self?.uploadTapped() }

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

    /// SFSafariViewController works inside share extensions where UIApplication.open and
    /// NSExtensionContext.open silently fail. The browser presents modally over our UI so
    /// the user can read the page and come back to finish the upload.
    private func openInAppBrowser(path: String) {
        guard let url = URL(string: "\(AppConfiguration.baseURL)\(path)") else { return }
        let safari = SFSafariViewController(url: url)
        safari.modalPresentationStyle = .pageSheet
        present(safari, animated: true)
    }

    // MARK: - Auth flow

    private func prepareAuthAndLoad() {
        if let creds = CredentialsManager.load() {
            loginCard.prefill(email: creds.email, password: creds.password)
            uploadService.setCredentials(email: creds.email, password: creds.password)
            loginCard.setBusy(true)
            uploadService.checkAuth { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.loginCard.setBusy(false)
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

    private func logIn(email: String, password: String) {
        uploadService.setCredentials(email: email, password: password)
        loginCard.setBusy(true)
        uploadService.checkAuth { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loginCard.setBusy(false)
                switch result {
                case let .success(serverEmail):
                    _ = CredentialsManager.save(Credentials(email: email, password: password))
                    self.didLogIn(email: serverEmail.isEmpty ? email : serverEmail)
                case .failure:
                    self.isLoggedIn = false
                    self.loginCard.setError("Invalid email or password")
                }
            }
        }
    }

    private func showLogin() {
        loginCard.isHidden = false
        albumCard.isHidden = true
        titleRow.setAccountMenu(nil)
        loginCard.setError(nil)
        refreshUploadButton()
    }

    private func didLogIn(email: String) {
        isLoggedIn = true
        view.endEditing(true)
        loginCard.isHidden = true
        albumCard.isHidden = false
        titleRow.setAccountMenu(accountMenu(email: email))
        albumCard.setLoading(true)
        loadAlbums()
        refreshUploadButton()
    }

    private func accountMenu(email: String) -> UIMenu {
        let signOut = UIAction(
            title: "Sign out",
            image: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmSignOut()
        }
        let header = email.isEmpty ? "Signed in" : "Signed in as \(email)"
        return UIMenu(title: header, children: [signOut])
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
        LastAlbumStore.forget()
        isLoggedIn = false
        selectedAlbumId = nil
        albums = []
        loginCard.clearFields()
        progressView.isHidden = true
        progressView.progress = 0
        showLogin()
        loginCard.focusEmail()
    }

    // MARK: - Shared media loading

    private func loadSharedItems() {
        guard let extensionContext,
              let items = extensionContext.inputItems as? [NSExtensionItem]
        else {
            AppLog.share.error("No extension context or input items")
            showError("No items to share")
            return
        }

        let attachmentCount = itemsLoader.load(from: items) { [weak self] batch in
            guard let self else { return }
            self.mediaItems = batch.items
            self.skippedCount = batch.skippedCount
            self.updateMediaSummary()
        }
        if attachmentCount == 0 {
            AppLog.share.error("No attachments found")
            showError("No media items found")
        }
    }

    private func updateMediaSummary() {
        let skipped = skippedCount > 0 ? " (\(skippedCount) skipped)" : ""

        if mediaItems.isEmpty {
            subtitleLabel.text = skippedCount > 0
                ? "Couldn't read \(skippedCount) shared item\(skippedCount == 1 ? "" : "s")"
                : "No valid media files found"
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
            subtitleLabel.text = "Ready to upload \(parts)" + skipped
        }
        refreshUploadButton()
    }

    private func refreshUploadButton() {
        bottomBar.isUploadEnabled = !isUploading
            && isLoggedIn
            && !mediaItems.isEmpty
            && selectedAlbumId != nil
    }

    // MARK: - Upload

    private func uploadTapped() {
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
        bottomBar.isCancelEnabled = false
        progressView.isHidden = false
        progressView.progress = 0
        subtitleLabel.text = "Uploading…"

        uploadService.upload(mediaItems: mediaItems, albumId: albumId) { [weak self] progress in
            DispatchQueue.main.async {
                guard let self, self.isUploading else { return }
                // Progress now arrives continuously, in small steps. Animating each one queues
                // overlapping 0.25s animations and the bar visibly lags the bytes, so only the
                // rare big jump — a whole file retiring — is animated.
                let value = Float(progress)
                self.progressView.setProgress(value, animated: value - self.progressView.progress > 0.05)
                self.subtitleLabel.text = "Uploading… \(Int(progress * 100))%"
            }
        } completion: { [weak self] outcome in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isUploading = false
                self.bottomBar.isCancelEnabled = true
                self.subtitleLabel.text = outcome.userMessage

                if outcome.allSucceeded {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                    }
                } else {
                    self.progressView.isHidden = true
                    self.refreshUploadButton()
                    self.showError(outcome.userMessage)
                }
            }
        }
    }

    private func cancelTapped() {
        extensionContext?.cancelRequest(withError: AppError.cancelled("User cancelled"))
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Albums

extension ShareViewController {
    func loadAlbums() {
        ShareAlbumsLoader.fetch(
            apiBaseURL: uploadService.getApiBaseUrl(),
            authorization: uploadService.getAuthorizationHeader()
        ) { [weak self] albums in
            guard let self else { return }
            self.albumCard.setLoading(false)

            guard let albums else {
                self.albumCard.setTitle("Failed to load albums")
                return
            }

            self.albums = albums
            self.applyAlbumMenu()
            if albums.isEmpty {
                self.albumCard.setTitle("No albums available")
                self.albumCard.isPickerEnabled = false
            } else {
                self.albumCard.isPickerEnabled = true
                if let id = AlbumPreselection.choose(from: albums.map(\.id), remembered: LastAlbumStore.albumId) {
                    self.selectAlbum(id: id)
                }
            }
        }
    }

    private func applyAlbumMenu() {
        let actions = albums.map { album in
            UIAction(
                title: "\(album.name) (\(album.fileCount))",
                state: album.id == selectedAlbumId ? .on : .off
            ) { [weak self] _ in
                self?.selectAlbum(id: album.id)
            }
        }
        albumCard.setMenu(UIMenu(title: "Choose album", options: .singleSelection, children: actions))
    }

    private func selectAlbum(id: Int) {
        selectedAlbumId = id
        // Both callers land here: the user tapping the menu, and the preselect on load. Saving
        // in both is deliberate — it lets a remembered id that points at a deleted album be
        // replaced by the fallback rather than being retried on every share.
        LastAlbumStore.remember(albumId: id)
        if let album = albums.first(where: { $0.id == id }) {
            albumCard.setTitle("\(album.name) (\(album.fileCount))")
        }
        applyAlbumMenu()
        refreshUploadButton()
    }
}
