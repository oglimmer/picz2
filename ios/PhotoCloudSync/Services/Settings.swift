import CryptoKit
import Foundation

final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var wifiOnly: Bool {
        didSet { defaults.set(wifiOnly, forKey: Keys.wifiOnly) }
    }

    @Published var lastSyncDate: Date? {
        didSet { defaults.set(lastSyncDate, forKey: Keys.lastSyncDate) }
    }

    @Published var albumId: Int {
        didSet { defaults.set(albumId, forKey: Keys.albumId) }
    }

    @Published var selectedAlbumName: String? {
        didSet { defaults.set(selectedAlbumName, forKey: Keys.selectedAlbumName) }
    }

    @Published var syncLastDays: Int {
        didSet { defaults.set(syncLastDays, forKey: Keys.syncLastDays) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let wifiOnly = "settings.wifiOnly"
        static let lastSyncDate = "settings.lastSyncDate"
        static let albumId = "settings.albumId"
        static let selectedAlbumName = "settings.selectedAlbumName"
        static let syncLastDays = "settings.syncLastDays"
    }

    private init() {
        wifiOnly = defaults.object(forKey: Keys.wifiOnly) as? Bool ?? true
        lastSyncDate = defaults.object(forKey: Keys.lastSyncDate) as? Date
        albumId = defaults.object(forKey: Keys.albumId) as? Int ?? 1
        selectedAlbumName = defaults.object(forKey: Keys.selectedAlbumName) as? String
        syncLastDays = defaults.object(forKey: Keys.syncLastDays) as? Int ?? 3
    }

    func clear() {
        defaults.removeObject(forKey: Keys.wifiOnly)
        defaults.removeObject(forKey: Keys.lastSyncDate)
        defaults.removeObject(forKey: Keys.albumId)
        defaults.removeObject(forKey: Keys.selectedAlbumName)
        defaults.removeObject(forKey: Keys.syncLastDays)

        // Reset to default values
        wifiOnly = true
        lastSyncDate = nil
        albumId = 1
        selectedAlbumName = nil
        syncLastDays = 3
    }
}

final class UploadStore {
    static let shared = UploadStore()

    private let defaults = UserDefaults.standard
    private let key = "uploads.completed.ids"
    private let checksumKey = "uploads.checksums"
    private let uploadingKey = "uploads.uploading.ids"
    private var set: Set<String>
    private var uploadingSet: Set<String>
    private let queue = DispatchQueue(label: "com.photocloud.uploadstore", attributes: .concurrent)

    // Map checksum -> localIdentifier
    private var checksumToLocalId: [String: String]

    private init() {
        let arr = defaults.stringArray(forKey: key) ?? []
        set = Set(arr)

        let uploadingArr = defaults.stringArray(forKey: uploadingKey) ?? []
        uploadingSet = Set(uploadingArr)

        if let data = defaults.data(forKey: checksumKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data)
        {
            checksumToLocalId = dict
        } else {
            checksumToLocalId = [:]
        }
    }

    func isUploaded(_ localId: String) -> Bool {
        queue.sync {
            set.contains(localId) || uploadingSet.contains(localId)
        }
    }

    func markAsUploading(_ localId: String) {
        queue.async(flags: .barrier) {
            self.uploadingSet.insert(localId)
            self.defaults.set(Array(self.uploadingSet), forKey: self.uploadingKey)
        }
    }

    func removeFromUploading(_ localId: String) {
        queue.async(flags: .barrier) {
            self.uploadingSet.remove(localId)
            self.defaults.set(Array(self.uploadingSet), forKey: self.uploadingKey)
        }
    }

    func markUploaded(_ localId: String, checksum: String? = nil) {
        queue.async(flags: .barrier) {
            self.set.insert(localId)
            self.uploadingSet.remove(localId)
            self.defaults.set(Array(self.set), forKey: self.key)
            self.defaults.set(Array(self.uploadingSet), forKey: self.uploadingKey)

            // Store checksum mapping if provided
            if let checksum {
                self.checksumToLocalId[checksum] = localId
                self.saveChecksums()
            }
        }
    }

    func reconcileWithServerChecksums(_ serverChecksums: [String]) {
        queue.async(flags: .barrier) {
            // Mark all assets with matching checksums as uploaded
            for checksum in serverChecksums {
                if let localId = self.checksumToLocalId[checksum] {
                    self.set.insert(localId)
                    self.uploadingSet.remove(localId)
                }
            }
            self.defaults.set(Array(self.set), forKey: self.key)
            self.defaults.set(Array(self.uploadingSet), forKey: self.uploadingKey)
        }
    }

    func storeChecksumMapping(checksum: String, localId: String) {
        queue.async(flags: .barrier) {
            self.checksumToLocalId[checksum] = localId
            self.saveChecksums()
        }
    }

    private func saveChecksums() {
        if let data = try? JSONEncoder().encode(checksumToLocalId) {
            defaults.set(data, forKey: checksumKey)
        }
    }

    func clear() {
        queue.async(flags: .barrier) {
            self.set.removeAll()
            self.uploadingSet.removeAll()
            self.checksumToLocalId.removeAll()
            self.defaults.removeObject(forKey: self.key)
            self.defaults.removeObject(forKey: self.uploadingKey)
            self.defaults.removeObject(forKey: self.checksumKey)
        }
    }

    func cleanupStaleUploading(activeTasks: Set<String> = []) {
        queue.async(flags: .barrier) {
            // Only clear uploading entries that don't have active URLSession tasks
            // This prevents re-uploading images that are still uploading in background
            let staleEntries = self.uploadingSet.subtracting(activeTasks)
            for entry in staleEntries {
                self.uploadingSet.remove(entry)
            }
            self.defaults.set(Array(self.uploadingSet), forKey: self.uploadingKey)

            if !staleEntries.isEmpty {
                print("UploadStore: Cleaned up \(staleEntries.count) stale uploading entries")
            }
            if !activeTasks.isEmpty {
                print("UploadStore: Preserved \(activeTasks.count) active upload tasks")
            }
        }
    }
}

// Helper to compute SHA-256 checksum
extension Data {
    func sha256() -> String {
        let hash = SHA256.hash(data: self)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
