import Social
import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    private var statusLabel: UILabel!
    private var progressView: UIProgressView!
    private var itemCountLabel: UILabel!
    private var uploadButton: UIButton!
    private var cancelButton: UIButton!
    private var albumPicker: UIPickerView!

    // Login UI
    private var emailField: UITextField!
    private var passwordField: UITextField!
    private var loginButton: UIButton!
    private var loginErrorLabel: UILabel!

    private var mediaItems: [MediaItem] = []
    private let uploadService = UploadService.shared
    private var loadedItemCount = 0
    private var totalItemCount = 0
    private var albums: [[String: Any]] = []
    private var selectedAlbumId: Int?
    private var isLoggedIn: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()

        print("🟢 ShareViewController viewDidLoad - Extension started")

        setupUI()
        prepareAuthAndLoad()
        loadSharedItems()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Status label
        statusLabel = UILabel()
        statusLabel.text = "Preparing media files..."
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // Item count label
        itemCountLabel = UILabel()
        itemCountLabel.text = ""
        itemCountLabel.font = .systemFont(ofSize: 13)
        itemCountLabel.textAlignment = .center
        itemCountLabel.textColor = .secondaryLabel
        itemCountLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(itemCountLabel)

        // Login fields
        emailField = UITextField()
        emailField.placeholder = "Email"
        emailField.borderStyle = .roundedRect
        emailField.autocapitalizationType = .none
        emailField.keyboardType = .emailAddress
        emailField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emailField)

        passwordField = UITextField()
        passwordField.placeholder = "Password"
        passwordField.borderStyle = .roundedRect
        passwordField.isSecureTextEntry = true
        passwordField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordField)

        loginButton = UIButton(type: .system)
        loginButton.setTitle("Login", for: .normal)
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loginButton)

        loginErrorLabel = UILabel()
        loginErrorLabel.text = ""
        loginErrorLabel.textColor = .systemRed
        loginErrorLabel.font = .systemFont(ofSize: 13)
        loginErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loginErrorLabel)

        // Album picker
        albumPicker = UIPickerView()
        albumPicker.delegate = self
        albumPicker.dataSource = self
        albumPicker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(albumPicker)

        // Progress view
        progressView = UIProgressView(progressViewStyle: .default)
        progressView.progress = 0
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)

        // Upload button
        uploadButton = UIButton(type: .system)
        uploadButton.setTitle("Upload", for: .normal)
        uploadButton.addTarget(self, action: #selector(uploadTapped), for: .touchUpInside)
        uploadButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(uploadButton)

        // Cancel button
        cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        // Layout constraints
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            itemCountLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            itemCountLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            itemCountLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            emailField.topAnchor.constraint(equalTo: itemCountLabel.bottomAnchor, constant: 20),
            emailField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            emailField.widthAnchor.constraint(equalToConstant: 180),
            emailField.heightAnchor.constraint(equalToConstant: 40),

            passwordField.topAnchor.constraint(equalTo: itemCountLabel.bottomAnchor, constant: 20),
            passwordField.leadingAnchor.constraint(equalTo: emailField.trailingAnchor, constant: 10),
            passwordField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            passwordField.heightAnchor.constraint(equalToConstant: 40),

            loginButton.topAnchor.constraint(equalTo: emailField.bottomAnchor, constant: 10),
            loginButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            loginButton.widthAnchor.constraint(equalToConstant: 100),

            loginErrorLabel.centerYAnchor.constraint(equalTo: loginButton.centerYAnchor),
            loginErrorLabel.leadingAnchor.constraint(equalTo: loginButton.trailingAnchor, constant: 10),
            loginErrorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            albumPicker.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 20),
            albumPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            albumPicker.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            albumPicker.heightAnchor.constraint(equalToConstant: 120),

            progressView.topAnchor.constraint(equalTo: albumPicker.bottomAnchor, constant: 20),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.widthAnchor.constraint(equalToConstant: 160),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),

            uploadButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            uploadButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            uploadButton.widthAnchor.constraint(equalToConstant: 160),
            uploadButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func prepareAuthAndLoad() {
        // Try loading saved credentials
        if let creds = CredentialsManager.load() {
            emailField.text = creds.email
            passwordField.text = creds.password
            uploadService.setCredentials(email: creds.email, password: creds.password)
            uploadService.checkAuth { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.isLoggedIn = true
                        self?.toggleLoginUI(hidden: true)
                        self?.loadAlbums()
                    case .failure:
                        self?.isLoggedIn = false
                        self?.toggleLoginUI(hidden: false)
                    }
                }
            }
        } else {
            toggleLoginUI(hidden: false)
        }
    }

    private func toggleLoginUI(hidden: Bool) {
        emailField.isHidden = hidden
        passwordField.isHidden = hidden
        loginButton.isHidden = hidden
        loginErrorLabel.text = ""
    }

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

                // Try to load as file URL (works best with Photos.app)
                if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    print("   ✅ Has file URL type - loading...")
                    attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] urlData, error in
                        if let error {
                            print("   ❌ File URL load error: \(error.localizedDescription)")
                        }
                        print("   📥 Received data type: \(type(of: urlData))")

                        if let url = urlData as? URL {
                            print("   ✅ Successfully cast to URL")
                            self?.handleLoadedURL(url: url, error: error)
                        } else if let urlData = urlData as? Data {
                            print("   ⚠️ Received Data instead of URL, trying to convert...")
                            if let urlString = String(data: urlData, encoding: .utf8), let url = URL(string: urlString) {
                                print("   ✅ Converted Data to URL: \(url.path)")
                                self?.handleLoadedURL(url: url, error: nil)
                            } else {
                                print("   ❌ Could not convert Data to URL")
                                self?.loadItemAlternative(attachment: attachment)
                            }
                        } else {
                            print("   ❌ URL cast failed, trying alternative loading...")
                            self?.loadItemAlternative(attachment: attachment)
                        }
                    }
                }
                // Check for images
                else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
                        self?.handleLoadedItem(item: item, error: error, type: .image)
                    }
                }
                // Check for videos
                else if attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] item, error in
                        self?.handleLoadedItem(item: item, error: error, type: .video)
                    }
                }
            }
        }
    }

    private func updateUI() {
        print("🔄 Updating UI - \(mediaItems.count) items loaded")

        if mediaItems.isEmpty {
            statusLabel.text = "No valid media files found"
            uploadButton.isEnabled = false
        } else {
            let imageCount = mediaItems.count(where: { $0.type == .image })
            let videoCount = mediaItems.count(where: { $0.type == .video })

            var description = "\(mediaItems.count) item\(mediaItems.count == 1 ? "" : "s")"
            if imageCount > 0, videoCount > 0 {
                description = "\(imageCount) photo\(imageCount == 1 ? "" : "s"), \(videoCount) video\(videoCount == 1 ? "" : "s")"
            } else if imageCount > 0 {
                description = "\(imageCount) photo\(imageCount == 1 ? "" : "s")"
            } else if videoCount > 0 {
                description = "\(videoCount) video\(videoCount == 1 ? "" : "s")"
            }

            statusLabel.text = "Ready to upload"
            itemCountLabel.text = description

            // Enable upload button only if an album is selected
            uploadButton.isEnabled = selectedAlbumId != nil

            if selectedAlbumId == nil {
                statusLabel.text = "Select an album to upload"
            }
        }
    }

    @objc private func uploadTapped() {
        guard !mediaItems.isEmpty else { return }

        guard isLoggedIn else {
            showError("Please login first")
            return
        }

        guard let albumId = selectedAlbumId else {
            showError("Please select an album before uploading")
            return
        }

        uploadButton.isEnabled = false
        statusLabel.text = "Uploading..."
        progressView.progress = 0

        uploadService.upload(mediaItems: mediaItems, albumId: albumId) { [weak self] progress in
            DispatchQueue.main.async {
                self?.progressView.progress = Float(progress)
            }
        } completion: { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case let .success(count):
                    self.statusLabel.text = "Successfully uploaded \(count) item\(count == 1 ? "" : "s")!"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                    }

                case let .failure(error):
                    self.showError("Upload failed: \(error.localizedDescription)")
                    self.uploadButton.isEnabled = true
                }
            }
        }
    }

    @objc private func cancelTapped() {
        extensionContext?.cancelRequest(withError: NSError(domain: "PhotoUploader", code: 0, userInfo: [NSLocalizedDescriptionKey: "User cancelled"]))
    }

    @objc private func loginTapped() {
        let email = emailField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField.text ?? ""
        loginErrorLabel.text = ""
        guard !email.isEmpty, !password.isEmpty else {
            loginErrorLabel.text = "Email and password required"
            return
        }
        uploadService.setCredentials(email: email, password: password)
        uploadService.checkAuth { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    _ = CredentialsManager.save(Credentials(email: email, password: password))
                    self?.isLoggedIn = true
                    self?.toggleLoginUI(hidden: true)
                    self?.loadAlbums()
                case .failure:
                    self?.isLoggedIn = false
                    self?.loginErrorLabel.text = "Invalid email or password"
                }
            }
        }
    }

    private func showError(_ message: String) {
        statusLabel.text = message
        uploadButton.isEnabled = false

        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Media Loading Handlers

extension ShareViewController {
    func loadItemAlternative(attachment: NSItemProvider) {
        print("   🔄 Trying alternative loading method...")
        // Try loading as image
        if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            print("   📷 Loading as image type...")
            attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
                print("   📥 Image load result type: \(type(of: item))")
                self?.handleLoadedItem(item: item, error: error, type: .image)
            }
        }
        // Try loading as video
        else if attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            print("   🎬 Loading as video type...")
            attachment.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] item, error in
                print("   📥 Video load result type: \(type(of: item))")
                self?.handleLoadedItem(item: item, error: error, type: .video)
            }
        } else {
            print("   ❌ No alternative loading method available")
        }
    }

    func handleLoadedURL(url: URL, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            loadedItemCount += 1

            if let error {
                print("❌ Error loading URL: \(error.localizedDescription)")
                if loadedItemCount == totalItemCount {
                    updateUI()
                }
                return
            }

            print("✅ Loaded URL: \(url.path)")

            // Determine type from URL extension
            let ext = url.pathExtension.lowercased()
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp"]
            let videoExtensions = ["mov", "mp4", "m4v", "avi", "wmv", "flv", "mkv", "webm"]

            let type: MediaItem.MediaType = if imageExtensions.contains(ext) {
                .image
            } else if videoExtensions.contains(ext) {
                .video
            } else {
                // Default to image
                .image
            }

            let filename = url.lastPathComponent
            let mediaItem = MediaItem(url: url, type: type, filename: filename)
            mediaItems.append(mediaItem)

            if loadedItemCount == totalItemCount {
                updateUI()
            }
        }
    }

    func handleLoadedItem(item: NSSecureCoding?, error: Error?, type: MediaItem.MediaType) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            loadedItemCount += 1

            if let error {
                print("Error loading item: \(error.localizedDescription)")
                if loadedItemCount == totalItemCount {
                    updateUI()
                }
                return
            }

            if let url = item as? URL {
                let filename = url.lastPathComponent
                let mediaItem = MediaItem(url: url, type: type, filename: filename)
                mediaItems.append(mediaItem)
            }

            if loadedItemCount == totalItemCount {
                updateUI()
            }
        }
    }
}

// MARK: - Albums Management

extension ShareViewController {
    func loadAlbums() {
        let apiUrl = uploadService.getApiBaseUrl()
        guard let url = URL(string: "\(apiUrl)/albums") else {
            print("❌ Invalid albums API URL")
            return
        }

        var request = URLRequest(url: url)
        if let auth = uploadService.getAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            if let error {
                print("❌ Error loading albums: \(error.localizedDescription)")
                return
            }

            guard let data else {
                print("❌ No data received from albums API")
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = json["success"] as? Bool,
                   success,
                   let albums = json["albums"] as? [[String: Any]]
                {
                    print("✅ Loaded \(albums.count) albums")
                    DispatchQueue.main.async {
                        self.albums = albums
                        self.albumPicker.reloadAllComponents()
                        if !albums.isEmpty {
                            self.albumPicker.selectRow(0, inComponent: 0, animated: false)
                            if let firstAlbum = albums.first, let id = firstAlbum["id"] as? Int {
                                self.selectedAlbumId = id
                            }
                        }
                    }
                }
            } catch {
                print("❌ Error parsing albums JSON: \(error.localizedDescription)")
            }
        }

        task.resume()
    }
}

// MARK: - UIPickerView Delegate & DataSource

extension ShareViewController: UIPickerViewDelegate, UIPickerViewDataSource {
    func numberOfComponents(in _: UIPickerView) -> Int {
        1
    }

    func pickerView(_: UIPickerView, numberOfRowsInComponent _: Int) -> Int {
        albums.count
    }

    func pickerView(_: UIPickerView, titleForRow row: Int, forComponent _: Int) -> String? {
        guard row < albums.count else { return nil }
        let album = albums[row]
        if let name = album["name"] as? String,
           let fileCount = album["fileCount"] as? Int
        {
            return "\(name) (\(fileCount) photos)"
        }
        return album["name"] as? String
    }

    func pickerView(_: UIPickerView, didSelectRow row: Int, inComponent _: Int) {
        guard row < albums.count else { return }
        let album = albums[row]
        if let id = album["id"] as? Int {
            selectedAlbumId = id
            uploadButton.isEnabled = !mediaItems.isEmpty
            statusLabel.text = "Ready to upload"
        }
    }
}
