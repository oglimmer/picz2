import Foundation
import Photos

final class PhotoLibraryManager: NSObject, PHPhotoLibraryChangeObserver {
    static let shared = PhotoLibraryManager()

    override private init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func requestAuthorization(completion: @escaping (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { completion(status) }
        }
    }

    func fetchAllAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let res = PHAsset.fetchAssets(with: options)
        var list: [PHAsset] = []
        list.reserveCapacity(res.count)
        res.enumerateObjects { asset, _, _ in list.append(asset) }
        return list
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
