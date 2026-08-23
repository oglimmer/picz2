import Foundation
import Testing
@testable import Zyncloud

/// §6 step 7 — the documented `useTus` "never written vs explicitly false" behaviour, plus the
/// rest of the defaults. Each case drives its own `UserDefaults` suite.
struct SettingsTests {
    private func withScratchDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "test.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    // MARK: - useTus

    /// R3: TUS is the default for new installs and for anyone who never touched the toggle.
    @Test func useTusDefaultsToTrueWhenTheKeyWasNeverWritten() {
        withScratchDefaults { defaults in
            #expect(Settings(defaults: defaults).useTus)
        }
    }

    /// The distinction the comment in `Settings.init` is about: `object(forKey:)` returns nil
    /// only when the key was never written, so an explicit `false` is respected rather than
    /// being overwritten by the default. A `bool(forKey:)` here would silently force TUS on.
    @Test func anExplicitFalseIsRespectedRatherThanTreatedAsUnset() {
        withScratchDefaults { defaults in
            defaults.set(false, forKey: "settings.useTus")
            #expect(!Settings(defaults: defaults).useTus)
        }
    }

    @Test func anExplicitTrueIsAlsoHonoured() {
        withScratchDefaults { defaults in
            defaults.set(true, forKey: "settings.useTus")
            #expect(Settings(defaults: defaults).useTus)
        }
    }

    @Test func togglingUseTusOffPersists() {
        withScratchDefaults { defaults in
            let settings = Settings(defaults: defaults)
            settings.useTus = false

            #expect(!Settings(defaults: defaults).useTus)
        }
    }

    // MARK: - Other defaults

    @Test func freshInstallDefaults() {
        withScratchDefaults { defaults in
            let settings = Settings(defaults: defaults)
            #expect(settings.wifiOnly)
            #expect(settings.albumId == 1)
            #expect(settings.syncLastDays == 3)
            #expect(settings.lastSyncDate == nil)
            #expect(settings.selectedAlbumName == nil)
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
            settings.wifiOnly = false
            settings.albumId = 42
            settings.syncLastDays = 30
            settings.selectedAlbumName = "Holiday"
            settings.lastSyncDate = date

            let reloaded = Settings(defaults: defaults)
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
            settings.wifiOnly = false
            settings.albumId = 42
            settings.syncLastDays = 30
            settings.selectedAlbumName = "Holiday"
            settings.lastSyncDate = Date()
            settings.useTus = false

            settings.clear()

            #expect(settings.wifiOnly)
            #expect(settings.albumId == 1)
            #expect(settings.syncLastDays == 3)
            #expect(settings.selectedAlbumName == nil)
            #expect(settings.lastSyncDate == nil)
            #expect(settings.useTus)
        }
    }

    @Test func clearedValuesSurviveARestart() {
        withScratchDefaults { defaults in
            let settings = Settings(defaults: defaults)
            settings.useTus = false
            settings.albumId = 42

            settings.clear()

            let reloaded = Settings(defaults: defaults)
            #expect(reloaded.useTus)
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

            #expect(defaults.object(forKey: "settings.useTus") != nil)
            #expect(defaults.object(forKey: "settings.wifiOnly") != nil)
            // ...and the value written is the default, so behaviour is unaffected.
            #expect(Settings(defaults: defaults).useTus)
        }
    }
}
