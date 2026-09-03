import Foundation
import UIKit

/// What this build tells the server it is running on.
///
/// On Mac Catalyst `UIDevice` misreports on purpose: `model` returns "iPad", and `systemVersion`
/// returns the iOS release the macOS version is paired with, not the macOS version. Both values go
/// straight into the server's device list, where a Mac listed as "iPad / 26.0" is simply wrong.
/// `ProcessInfo` is not remapped under Catalyst, so it is the honest source there.
///
/// `isMacCatalystApp` is false on iOS, so there is one code path and no `#if` to keep in sync.
enum DeviceIdentity {
    static var model: String {
        isMacCatalyst ? "Mac" : UIDevice.current.model
    }

    static var osVersion: String {
        guard isMacCatalyst else { return UIDevice.current.systemVersion }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static var isMacCatalyst: Bool {
        ProcessInfo.processInfo.isMacCatalystApp
    }
}
