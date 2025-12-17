import Cocoa
import UniformTypeIdentifiers

class ShareViewController: NSViewController {
    @IBOutlet var statusLabel: NSTextField!
    @IBOutlet var progressIndicator: NSProgressIndicator!
    @IBOutlet var itemCountLabel: NSTextField!
    @IBOutlet var uploadButton: NSButton!
    @IBOutlet var cancelButton: NSButton!
    @IBOutlet var albumPopUpButton: NSPopUpButton!

    private var mediaItems: [MediaItem] = []
    private let uploadService = UploadService.shared
    private var loadedItemCount = 0
    private var totalItemCount = 0
    private var albums: [[String: Any]] = []
    private var selectedAlbumId: Int?
    private var isLoggedIn: Bool = false

    // Login UI
    private var emailField: NSTextField!
    private var passwordField: NSSecureTextField!
    private var loginButton: NSButton!
    private var loginErrorLabel: NSTextField!

    override func loadView() {
        // Create the view hierarchy programmatically
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        // Status label
        let statusLabel = NSTextField(labelWithString: "Preparing media files...")
        statusLabel.frame = NSRect(x: 20, y: 230, width: 360, height: 30)
        statusLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        statusLabel.alignment = .center
        view.addSubview(statusLabel)
        self.statusLabel = statusLabel

        // Item count label
        let itemCountLabel = NSTextField(labelWithString: "")
        itemCountLabel.frame = NSRect(x: 20, y: 200, width: 360, height: 20)
        itemCountLabel.font = NSFont.systemFont(ofSize: 13)
        itemCountLabel.alignment = .center
        itemCountLabel.textColor = .secondaryLabelColor
        view.addSubview(itemCountLabel)
        self.itemCountLabel = itemCountLabel

        // Login fields
        let emailField = NSTextField(string: "")
        emailField.placeholderString = "Email"
        emailField.frame = NSRect(x: 20, y: 195, width: 180, height: 24)
        view.addSubview(emailField)
        self.emailField = emailField

        let passwordField = NSSecureTextField()
        passwordField.stringValue = ""
        passwordField.placeholderString = "Password"
        passwordField.frame = NSRect(x: 210, y: 195, width: 170, height: 24)
        view.addSubview(passwordField)
        self.passwordField = passwordField

        let loginButton = NSButton(title: "Login", target: self, action: #selector(loginTapped))
        loginButton.frame = NSRect(x: 20, y: 165, width: 100, height: 26)
        loginButton.bezelStyle = .rounded
        view.addSubview(loginButton)
        self.loginButton = loginButton

        let loginErrorLabel = NSTextField(labelWithString: "")
        loginErrorLabel.frame = NSRect(x: 130, y: 165, width: 250, height: 26)
        loginErrorLabel.textColor = .systemRed
        view.addSubview(loginErrorLabel)
        self.loginErrorLabel = loginErrorLabel

        // Album selection label
        let albumLabel = NSTextField(labelWithString: "Album:")
        albumLabel.frame = NSRect(x: 20, y: 135, width: 60, height: 20)
        albumLabel.font = NSFont.systemFont(ofSize: 13)
        albumLabel.isEditable = false
        albumLabel.isBordered = false
        albumLabel.backgroundColor = .clear
        view.addSubview(albumLabel)

        // Album popup button
        let albumPopUpButton = NSPopUpButton(frame: NSRect(x: 85, y: 130, width: 295, height: 25))
        albumPopUpButton.autoenablesItems = false
        view.addSubview(albumPopUpButton)
        self.albumPopUpButton = albumPopUpButton

        // Progress indicator
        let progressIndicator = NSProgressIndicator()
        progressIndicator.frame = NSRect(x: 100, y: 110, width: 200, height: 20)
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.doubleValue = 0
        view.addSubview(progressIndicator)
        self.progressIndicator = progressIndicator

        // Upload button
        let uploadButton = NSButton(title: "Upload", target: self, action: #selector(uploadTapped))
        uploadButton.frame = NSRect(x: 220, y: 20, width: 160, height: 32)
        uploadButton.bezelStyle = .rounded
        uploadButton.keyEquivalent = "\r"
        view.addSubview(uploadButton)
        self.uploadButton = uploadButton

        // Cancel button
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.frame = NSRect(x: 20, y: 20, width: 160, height: 32)
        cancelButton.bezelStyle = .rounded
        view.addSubview(cancelButton)
        self.cancelButton = cancelButton

        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        print("🟢 ShareViewController viewDidLoad - Extension started")

        // Set preferred size
        preferredContentSize = NSSize(width: 400, height: 300)

        // Prepare auth and then load albums
        prepareAuthAndLoad()

        // Load shared items
        loadSharedItems()
    }

    private func prepareAuthAndLoad() {
        // Try loading saved credentials
        if let creds = CredentialsManager.load() {
            emailField.stringValue = creds.email
            passwordField.stringValue = creds.password
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
        loginErrorLabel.stringValue = ""
    }

    private func loadAlbums() {
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
                DispatchQueue.main.async {
                    self.setupAlbumPopup(with: [])
                }
                return
            }

            guard let data else {
                print("❌ No data received from albums API")
                DispatchQueue.main.async {
                    self.setupAlbumPopup(with: [])
                }
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
                        self.setupAlbumPopup(with: albums)
                    }
                } else {
                    print("❌ Invalid albums response format")
                    DispatchQueue.main.async {
                        self.setupAlbumPopup(with: [])
                    }
                }
            } catch {
                print("❌ Error parsing albums JSON: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.setupAlbumPopup(with: [])
                }
            }
        }

        task.resume()
    }

    private func setupAlbumPopup(with albums: [[String: Any]]) {
        albumPopUpButton.removeAllItems()
        albumPopUpButton.target = self
        albumPopUpButton.action = #selector(albumSelectionChanged)

        // Add placeholder option
        albumPopUpButton.addItem(withTitle: "Select an album...")
        albumPopUpButton.item(at: 0)?.representedObject = nil
        albumPopUpButton.item(at: 0)?.isEnabled = false

        // Add albums
        for album in albums {
            if let name = album["name"] as? String,
               let id = album["id"] as? Int,
               let fileCount = album["fileCount"] as? Int
            {
                let title = "\(name) (\(fileCount) photos)"
                albumPopUpButton.addItem(withTitle: title)
                if let item = albumPopUpButton.lastItem {
                    item.representedObject = id
                }
            }
        }

        albumPopUpButton.selectItem(at: 0)

        // Disable upload button until an album is selected
        uploadButton.isEnabled = false
    }

    @objc private func albumSelectionChanged() {
        // Update upload button state when album selection changes
        let hasAlbumSelected = albumPopUpButton.indexOfSelectedItem > 0
        uploadButton.isEnabled = hasAlbumSelected && !mediaItems.isEmpty

        if hasAlbumSelected {
            statusLabel.stringValue = "Ready to upload"
        } else {
            statusLabel.stringValue = "Select an album to upload"
        }
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
                    let options: [AnyHashable: Any] = [NSItemProviderPreferredImageSizeKey: NSValue(size: NSSize.zero)]
                    attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: options) { [weak self] urlData, error in
                        if let error {
                            print("   ❌ File URL load error: \(error.localizedDescription)")
                            self?.handleLoadedURL(url: URL(fileURLWithPath: "/dev/null"), error: error)
                            return
                        }
                        print("   📥 Received data type: \(type(of: urlData))")

                        if let url = urlData as? URL {
                            print("   ✅ Successfully cast to URL: \(url.path)")
                            self?.handleLoadedURL(url: url, error: nil)
                        } else if let urlData = urlData as? Data {
                            print("   ⚠️ Received Data instead of URL, trying to convert...")
                            if let urlString = String(data: urlData, encoding: .utf8), let url = URL(string: urlString) {
                                print("   ✅ Converted Data to URL: \(url.path)")
                                self?.handleLoadedURL(url: url, error: nil)
                            } else {
                                print("   ❌ Could not convert Data to URL")
                                self?.loadItemAlternative(attachment: attachment)
                            }
                        } else if let securedResource = urlData {
                            // Handle _EXItemProviderSandboxedResource or other wrapped types
                            print("   🔓 Attempting to extract URL from sandboxed resource...")
                            let mirror = Mirror(reflecting: securedResource)
                            var foundURL: URL?

                            for child in mirror.children {
                                if let url = child.value as? URL {
                                    foundURL = url
                                    break
                                }
                            }

                            if let url = foundURL {
                                print("   ✅ Extracted URL from sandboxed resource: \(url.path)")
                                self?.handleLoadedURL(url: url, error: nil)
                            } else {
                                print("   ❌ Could not extract URL from resource, trying alternative loading...")
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
                // Check for generic video types
                else if attachment.hasItemConformingToTypeIdentifier(UTType.video.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.video.identifier, options: nil) { [weak self] item, error in
                        self?.handleLoadedItem(item: item, error: error, type: .video)
                    }
                }
            }
        }
    }

    private func loadItemAlternative(attachment: NSItemProvider) {
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

    private func handleLoadedURL(url: URL, error: Error?) {
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

    private func handleLoadedItem(item: NSSecureCoding?, error: Error?, type: MediaItem.MediaType) {
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

    private func updateUI() {
        print("🔄 Updating UI - \(mediaItems.count) items loaded")

        if mediaItems.isEmpty {
            statusLabel.stringValue = "No valid media files found"
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

            statusLabel.stringValue = "Ready to upload"
            itemCountLabel.stringValue = description

            // Enable upload button only if an album is selected (not "No album")
            let hasAlbumSelected = albumPopUpButton.indexOfSelectedItem > 0
            uploadButton.isEnabled = hasAlbumSelected

            if !hasAlbumSelected {
                statusLabel.stringValue = "Select an album to upload"
            }
        }
    }

    @objc private func uploadTapped() {
        guard !mediaItems.isEmpty else { return }

        guard isLoggedIn else {
            showError("Please login first")
            return
        }

        // Get selected album ID (REQUIRED)
        guard let selectedItem = albumPopUpButton.selectedItem,
              let albumId = selectedItem.representedObject as? Int
        else {
            showError("Please select an album before uploading")
            return
        }

        selectedAlbumId = albumId

        uploadButton.isEnabled = false
        statusLabel.stringValue = "Uploading..."
        progressIndicator.doubleValue = 0

        uploadService.upload(mediaItems: mediaItems, albumId: selectedAlbumId) { [weak self] progress in
            DispatchQueue.main.async {
                self?.progressIndicator.doubleValue = progress * 100
            }
        } completion: { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case let .success(count):
                    self.statusLabel.stringValue = "Successfully uploaded \(count) item\(count == 1 ? "" : "s")!"
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
        let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue
        loginErrorLabel.stringValue = ""
        guard !email.isEmpty, !password.isEmpty else {
            loginErrorLabel.stringValue = "Email and password required"
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
                    self?.loginErrorLabel.stringValue = "Invalid email or password"
                }
            }
        }
    }

    private func showError(_ message: String) {
        statusLabel.stringValue = message
        uploadButton.isEnabled = false

        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
