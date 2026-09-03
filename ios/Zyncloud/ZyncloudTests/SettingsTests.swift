import Foundation
import Testing
@testable import Zyncloud

/// §6 step 7 — the persisted settings defaults, and that `clear()` restores them.
/// Each case drives its own `UserDefaults` suite.
struct SettingsTests {
    private func withScratchDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "test.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    // MARK: - Defaults

    @Test func freshInstallDefaults() {
        withScratchDefaults { defaults in
            let settings = Settings(defaults: defaults)
            #expect(settings.syncEnabled)
            #expect(settings.wifiOnly)
            #expect(settings.albumId == 1)
            #expect(settings.syncLastDays == 3)
            #expect(settings.lastSyncDate == nil)
            #expect(settings.selectedAlbumName == nil)
        }
    }

    /// The one default that must not flip to `false` by accident: a fresh install with it off
    /// would look installed and backed up and never upload a byte.
    @Test func syncEnabledRespectsAnExplicitFalse() {
        withScratchDefaults { defaults in
            defaults.set(false, forKey: "settings.syncEnabled")
            #expect(!Settings(defaults: defaults).syncEnabled)
        }
    }

    @Test func wifiOnlyRespectsAnExplicitFalse() {
        withScratchDefaults { defaults in
            defaults.set(false, forKey: "settings.wifiOnly")
            #expect(!Settings(defaults: defaults).wifiOnly)
        }
    }

    @Test func everySettingSurvivesARestart() {
        withScratchDefaults { defaults in
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            let settings = Settings(defaults: defaults)
            settings.syncEnabled = false
            settings.wifiOnly = false
            settings.albumId = 42
            settings.syncLastDays = 30
            settings.selectedAlbumName = "Holiday"
            settings.lastSyncDate = date

            let reloaded = Settings(defaults: defaults)
            #expect(!reloaded.syncEnabled)
            #expect(!reloaded.wifiOnly)
            #expect(reloaded.albumId == 42)
            #expect(reloaded.syncLastDays == 30)
            #expect(reloaded.selectedAlbumName == "Holiday")
            #expect(reloaded.lastSyncDate == date)
        }
    }

    // MARK: - clear

    @Test func clearRestoresEveryDefault() {
        withScratchDefaults { defaults in
            let settings = Settings(defaults: defaults)
            settings.syncEnabled = false
            settings.wifiOnly = false
            settings.albumId = 42
            settings.syncLastDays = 30
            settings.selectedAlbumName = "Holiday"
            settings.lastSyncDate = Date()

            settings.clear()

            // Logging out and back in on a phone that had been switched off must not leave the
            // next account switched off too — the switch is about this device, not this login.
            #expect(settings.syncEnabled)
            #expect(settings.wifiOnly)
            #expect(settings.albumId == 1)
            #expect(settings.syncLastDays == 3)
            #expect(settings.selectedAlbumName == nil)
            #expect(settings.lastSyncDate == nil)
        }
    }

    @Test func clearedValuesSurviveARestart() {
        withScratchDefaults { defaults in
            let settings = Settings(defaults: defaults)
            settings.albumId = 42

            settings.clear()

            let reloaded = Settings(defaults: defaults)
            #expect(reloaded.albumId == 1)
        }
    }

    /// Documents a quirk rather than desired behaviour: `clear()` removes each key and then
    /// assigns the default value, whose `didSet` writes the key straight back. So after a
    /// logout the keys exist again and "never written" is no longer distinguishable from
    /// "explicitly set to the default". Harmless today because the written value *is* the
    /// default — but it means `clear()` cannot be used to restore first-launch semantics.
    @Test func clearRewritesTheKeysItJustRemoved() {
        withScratchDefaults { defaults in
            let settings = Settings(defaults: defaults)
            settings.clear()

            #expect(defaults.object(forKey: "settings.wifiOnly") != nil)
            #expect(defaults.object(forKey: "settings.syncLastDays") != nil)
            // ...and the value written is the default, so behaviour is unaffected.
            #expect(Settings(defaults: defaults).wifiOnly)
        }
    }
}
