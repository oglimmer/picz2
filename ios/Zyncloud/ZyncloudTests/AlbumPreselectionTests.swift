import Foundation
import Testing
@testable import Zyncloud

/// The share sheet used to open on `albums.first` every time, so a user with one working album
/// and several old ones re-picked the same destination on every share.
struct AlbumPreselectionTests {
    @Test("with nothing remembered, the first album wins")
    func firstAlbumIsTheFallback() {
        #expect(AlbumPreselection.choose(from: [7, 3, 9], remembered: nil) == 7)
    }

    @Test("the remembered album is preferred over the first")
    func rememberedWins() {
        #expect(AlbumPreselection.choose(from: [7, 3, 9], remembered: 9) == 9)
    }

    @Test("a remembered album the account no longer has falls back to the first")
    func deletedAlbumFallsBack() {
        #expect(AlbumPreselection.choose(from: [7, 3], remembered: 9) == 7)
    }

    @Test("no albums means nothing to preselect")
    func emptyAccount() {
        #expect(AlbumPreselection.choose(from: [], remembered: 9) == nil)
        #expect(AlbumPreselection.choose(from: [], remembered: nil) == nil)
    }
}

/// `.serialized` because ``LastAlbumStore/defaults`` is a static seam — the same reason
/// ``CredentialsManagerTests`` is serialized. Parallel cases would swap the scratch suite out
/// from under each other.
@Suite(.serialized)
struct LastAlbumStoreTests {
    /// A scratch suite, so a test run never touches the signed-in user's remembered album.
    private func withScratchDefaults(_ body: () -> Void) {
        let name = "LastAlbumStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let previous = LastAlbumStore.defaults
        LastAlbumStore.defaults = defaults
        defer {
            LastAlbumStore.defaults = previous
            defaults.removePersistentDomain(forName: name)
        }
        body()
    }

    @Test("nothing chosen yet reads as nil, not as album 0")
    func unsetIsNil() {
        withScratchDefaults {
            #expect(LastAlbumStore.albumId == nil)
        }
    }

    @Test("a remembered album survives to the next share")
    func remembersAcrossReads() {
        withScratchDefaults {
            LastAlbumStore.remember(albumId: 42)
            #expect(LastAlbumStore.albumId == 42)
        }
    }

    @Test("the newest choice replaces the previous one")
    func overwrites() {
        withScratchDefaults {
            LastAlbumStore.remember(albumId: 42)
            LastAlbumStore.remember(albumId: 43)
            #expect(LastAlbumStore.albumId == 43)
        }
    }

    @Test("signing out drops the album so the next account does not inherit it")
    func forgetClears() {
        withScratchDefaults {
            LastAlbumStore.remember(albumId: 42)
            LastAlbumStore.forget()
            #expect(LastAlbumStore.albumId == nil)
        }
    }

    @Test("album 0 is stored and read back as 0, not as unset")
    func zeroIsAValue() {
        withScratchDefaults {
            LastAlbumStore.remember(albumId: 0)
            #expect(LastAlbumStore.albumId == 0)
        }
    }
}
