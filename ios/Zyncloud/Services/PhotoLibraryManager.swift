import Foundation
// `@preconcurrency` because `PHAsset` and friends are not `Sendable` and never will be — they
// are Objective-C objects backed by the photo library's own thread-safe store. Assets are
// passed between the scan queue and the upload queues throughout, which is what the Photos
// framework is designed for; the annotation says "these crossings are Apple's problem, not a
// race we introduced".
@preconcurrency import Photos

/// - Note: `@unchecked Sendable` — this type holds no mutable state of its own. It is a stateless
///   wrapper over `PHPhotoLibrary`, which is thread-safe, plus a change-observer registration.
final class PhotoLibraryManager: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    static let shared = PhotoLibraryManager()

    override private init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func requestAuthorization(completion: @escaping @Sendable (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { completion(status) }
        }
    }

    func fetchAssets(lastDays: Int) -> [PHAsset] {
        let calendar = Calendar.current
        let now = Date()
        guard let cutoffDate = calendar.date(byAdding: .day, value: -lastDays, to: now) else {
            return []
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(format: "creationDate >= %@", cutoffDate as NSDate)
        let res = PHAsset.fetchAssets(with: options)
        var list: [PHAsset] = []
        list.reserveCapacity(res.count)
        res.enumerateObjects { asset, _, _ in list.append(asset) }
        return list
    }

    func fetchAssets(since date: Date) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(format: "creationDate > %@", date as NSDate)
        let res = PHAsset.fetchAssets(with: options)
        var list: [PHAsset] = []
        list.reserveCapacity(res.count)
        res.enumerateObjects { asset, _, _ in list.append(asset) }
        return list
    }

    // We keep it simple: any change triggers a new incremental sync run.
    func photoLibraryDidChange(_: PHChange) {
        SyncCoordinator.shared.handlePhotoLibraryDidChange()
    }
}
