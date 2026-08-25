import Combine
import Foundation

/// Backs the two account-level settings screens: narration languages and tags.
///
/// Both live on the user, not on an album, so one view model owns both and each screen reads the
/// part it needs. That also means the tag list is loaded once when either screen opens.
@MainActor
class UserSettingsViewModel: ViewModelProtocol {
    @Published var isLoading: Bool = false
    @Published var alertState: AlertState?

    // Narration languages
    @Published var language1: String = ""
    @Published var language2: String = ""
    @Published var isSavingLanguages: Bool = false

    // Tags
    @Published var tags: [Tag] = []
    @Published var isLoadingTags: Bool = false
    @Published var isMutatingTag: Bool = false

    /// Last values the server confirmed. A failed save rolls the field back to these rather than
    /// leaving the text field showing a name that was never stored.
    private var savedLanguage1: String = ""
    private var savedLanguage2: String = ""

    private var apiClient: APIClient?

    init() {
        if let credentials = KeychainHelper.shared.load() {
            apiClient = APIClient(
                username: credentials.username,
                password: credentials.password,
            )
        }
    }

    private func requireClient() -> APIClient? {
        guard let apiClient else {
            alertState = AlertState(
                title: "Error",
                message: "Not authenticated. Please log in again.",
            )
            return nil
        }
        return apiClient
    }

    // MARK: - Narration Languages

    func loadLanguages() {
        guard let apiClient = requireClient() else { return }

        isLoading = true

        apiClient.fetchLanguageSettings { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false

                switch result {
                case let .success(response):
                    // The server may answer with nulls before anything was ever set; the web app
                    // shows the same two defaults in that case.
                    self.savedLanguage1 = response.language1 ?? "German"
                    self.savedLanguage2 = response.language2 ?? "English"
                    self.language1 = self.savedLanguage1
                    self.language2 = self.savedLanguage2
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    /// `slot` is 1 or 2. Called on commit (return key or focus loss), not per keystroke.
    func saveLanguage(slot: Int) {
        guard let apiClient = requireClient() else { return }

        let entered = (slot == 1 ? language1 : language2).trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = slot == 1 ? savedLanguage1 : savedLanguage2

        guard !entered.isEmpty else {
            alertState = AlertState(
                title: "Name Required",
                message: "A narration language name cannot be empty.",
            )
            rollbackLanguage(slot: slot)
            return
        }

        guard entered != saved else { return }

        isSavingLanguages = true

        apiClient.setLanguageName(slot: slot, name: entered) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isSavingLanguages = false

                switch result {
                case .success:
                    if slot == 1 {
                        self.savedLanguage1 = entered
                        self.language1 = entered
                    } else {
                        self.savedLanguage2 = entered
                        self.language2 = entered
                    }
                case let .failure(error):
                    self.rollbackLanguage(slot: slot)
                    self.handleError(error)
                }
            }
        }
    }

    private func rollbackLanguage(slot: Int) {
        if slot == 1 {
            language1 = savedLanguage1
        } else {
            language2 = savedLanguage2
        }
    }

    // MARK: - Tags

    func loadTags() {
        guard let apiClient = requireClient() else { return }

        isLoadingTags = true

        apiClient.fetchTags { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoadingTags = false

                switch result {
                case let .success(tags):
                    self.tags = tags
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    func createTag(name: String) {
        guard let apiClient = requireClient() else { return }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alertState = AlertState(title: "Name Required", message: "Enter a tag name first.")
            return
        }

        isMutatingTag = true

        apiClient.createTag(name: trimmed) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isMutatingTag = false

                switch result {
                case let .success(tag):
                    if let tag {
                        self.tags.append(tag)
                    } else {
                        // Created, but the server did not echo the row back — refetch rather
                        // than guess at an id.
                        self.loadTags()
                    }
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    func renameTag(_ tag: Tag, to name: String) {
        guard let apiClient = requireClient() else { return }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != tag.name else { return }

        guard !tag.isSystem else {
            alertState = AlertState(
                title: "System Tag",
                message: "\"\(tag.name)\" is used by the gallery itself and cannot be renamed.",
            )
            return
        }

        isMutatingTag = true

        apiClient.updateTag(id: tag.id, name: trimmed) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isMutatingTag = false

                switch result {
                case let .success(updated):
                    guard let index = self.tags.firstIndex(where: { $0.id == tag.id }) else { return }
                    self.tags[index] = updated ?? Tag(id: tag.id, name: trimmed, createdAt: tag.createdAt)
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }

    func confirmDeleteTag(_ tag: Tag) {
        guard !tag.isSystem else {
            alertState = AlertState(
                title: "System Tag",
                message: "\"\(tag.name)\" is used by the gallery itself and cannot be deleted.",
            )
            return
        }

        alertState = .confirmation(
            title: "Delete Tag",
            message: "Delete \"\(tag.name)\"? It will be removed from every photo that carries it.",
            confirmTitle: "Delete",
            confirmAction: { [weak self] in
                self?.deleteTag(tag)
            },
        )
    }

    private func deleteTag(_ tag: Tag) {
        guard let apiClient = requireClient() else { return }

        isMutatingTag = true

        apiClient.deleteTag(id: tag.id) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isMutatingTag = false

                switch result {
                case .success:
                    self.tags.removeAll { $0.id == tag.id }
                case let .failure(error):
                    self.handleError(error)
                }
            }
        }
    }
}
