import Foundation
import Testing
@testable import Zyncloud

/// The Wi‑Fi Only gate. The bug behind it: with the setting on and the phone on 5G,
/// `applyNetworkPolicy()` refused every upload request and URLSession reported -1009, which
/// the sync log showed as "Failed to upload …: The Internet connection appears to be offline".
/// Three of those tripped the export give-up rule, so a healthy phone logged errors about a
/// choice the user had made deliberately.
struct NetworkPolicyTests {
    // MARK: - Reading the path

    /// Nothing else about the path matters once it is unsatisfied — an airplane-mode path can
    /// still report stale cost flags.
    @Test(arguments: [false, true], [false, true])
    func anUnsatisfiedPathIsOfflineWhateverTheCostFlags(expensive: Bool, constrained: Bool) {
        let link = UploadLink(satisfied: false, isExpensive: expensive, isConstrained: constrained)
        #expect(link == .offline)
    }

    @Test func plainWiFiIsUnmetered() {
        #expect(UploadLink(satisfied: true, isExpensive: false, isConstrained: false) == .unmetered)
    }

    /// Cellular. `isExpensive` is what `allowsCellularAccess = false` refuses.
    @Test func anExpensiveLinkIsMetered() {
        #expect(UploadLink(satisfied: true, isExpensive: true, isConstrained: false) == .metered)
    }

    /// Low Data Mode. Wi-Fi by interface, refused all the same by
    /// `allowsConstrainedNetworkAccess = false` — so judging by interface type would have got
    /// this one wrong and produced the very -1009 this gate exists to predict.
    @Test func aConstrainedLinkIsMetered() {
        #expect(UploadLink(satisfied: true, isExpensive: false, isConstrained: true) == .metered)
    }

    // MARK: - The decision

    @Test func wiFiUploadsUnderEitherSetting() {
        #expect(UploadNetworkPolicy.uploadsAllowed(link: .unmetered, wifiOnly: true))
        #expect(UploadNetworkPolicy.uploadsAllowed(link: .unmetered, wifiOnly: false))
    }

    /// The case in the screenshot: 5G, Wi‑Fi Only on.
    @Test func cellularIsBlockedOnlyWhileWiFiOnlyIsOn() {
        #expect(!UploadNetworkPolicy.uploadsAllowed(link: .metered, wifiOnly: true))
        #expect(UploadNetworkPolicy.uploadsAllowed(link: .metered, wifiOnly: false))
    }

    /// Turning Wi‑Fi Only off does not conjure a connection.
    @Test func offlineIsBlockedUnderEitherSetting() {
        #expect(!UploadNetworkPolicy.uploadsAllowed(link: .offline, wifiOnly: true))
        #expect(!UploadNetworkPolicy.uploadsAllowed(link: .offline, wifiOnly: false))
    }

    // MARK: - What the user is told

    @Test func aRunningLinkHasNoPauseToExplain() {
        #expect(UploadNetworkPolicy.pause(link: .unmetered, wifiOnly: true) == nil)
        #expect(UploadNetworkPolicy.pause(link: .metered, wifiOnly: false) == nil)
    }

    /// "No network" and "waiting for Wi-Fi" are different problems with different fixes, so
    /// they must not collapse into one message.
    @Test func theTwoPausesReadDifferently() {
        let offline = UploadNetworkPolicy.pause(link: .offline, wifiOnly: true)
        let metered = UploadNetworkPolicy.pause(link: .metered, wifiOnly: true)
        #expect(offline != nil)
        #expect(metered != nil)
        #expect(offline?.status != metered?.status)
        #expect(offline?.detail != metered?.detail)
    }

    /// The short one goes in a table cell next to its label; a sentence there is truncated.
    @Test func theStatusTextIsShortAndTheDetailIsNot() throws {
        for link in [UploadLink.offline, .metered] {
            let pause = try #require(UploadNetworkPolicy.pause(link: link, wifiOnly: true))
            #expect(!pause.status.isEmpty)
            #expect(pause.status.count <= 24)
            #expect(pause.detail.count > pause.status.count)
        }
    }

    /// Wi‑Fi Only is a setting the user can change, so the message that blames it says so —
    /// otherwise "waiting for Wi-Fi" on a phone with five bars of 5G reads as a fault.
    @Test func theMeteredPauseNamesTheSettingResponsible() {
        let detail = UploadNetworkPolicy.pause(link: .metered, wifiOnly: true)?.detail ?? ""
        #expect(detail.contains("Wi‑Fi Only"))
    }

    // MARK: - The monitor

    /// Fails open. A monitor that never reports must not become an app that never backs
    /// anything up — that is a worse failure than the log noise this replaces.
    @Test func anUnmeasuredLinkAllowsUploads() {
        let monitor = NetworkMonitor()
        #expect(monitor.currentLink == nil)
        #expect(monitor.uploadsAllowed(wifiOnly: true))
        #expect(monitor.pause(wifiOnly: true) == nil)
    }

    @Test func theMonitorAppliesThePolicyToItsCurrentLink() {
        let monitor = NetworkMonitor(initialLink: .metered)
        #expect(!monitor.uploadsAllowed(wifiOnly: true))
        #expect(monitor.pause(wifiOnly: true)?.status == "Waiting for Wi‑Fi")

        monitor.update(.unmetered)
        #expect(monitor.uploadsAllowed(wifiOnly: true))
        #expect(monitor.pause(wifiOnly: true) == nil)
    }

    /// Only changes are worth waking the coordinator for — `pathUpdateHandler` fires on
    /// unrelated route changes too, and each one would otherwise re-drain the queue.
    @Test func onlyARealChangeNotifies() {
        let monitor = NetworkMonitor(initialLink: .metered)
        let counter = Counter()
        monitor.onChange = { _ in counter.bump() }

        monitor.update(.metered)
        #expect(counter.value == 0)

        monitor.update(.unmetered)
        monitor.update(.unmetered)
        #expect(counter.value == 1)
    }

    /// `onChange` is called on the monitor's own queue, so the tally has to be safe to touch
    /// from there as well as from the test.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func bump() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }
}
