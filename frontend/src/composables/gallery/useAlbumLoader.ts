import type { Ref } from "vue";

export interface AlbumLoaderDeps {
  isLoggedIn: Ref<boolean>;
  loadAlbumById: (albumId: number, presentation: boolean) => Promise<unknown>;
  loadAlbumFiles: (albumId: number, presentation: boolean) => Promise<void>;
  loadTags: () => Promise<void>;
  loadEnabledAlbumTags: (albumId: number) => Promise<void>;
  clearEnabledAlbumTags: () => void;
  loadLanguageSettings: () => Promise<void>;
  loadRecordings: (albumId: number) => Promise<unknown>;
  loadGroups: (albumId: number) => Promise<void>;
}

export interface AlbumLoader {
  /** Loads everything the gallery shows for one album, in the one order that works. */
  load: (albumId: number, presentation: boolean) => Promise<void>;
  /** Re-fetches just the file list of the album loaded last. */
  reloadFiles: () => Promise<void>;
}

/**
 * The one load sequence for the gallery view, used on mount, when the route's album changes and
 * when presentation mode flips. It used to be written out three times.
 *
 * <p>Cancellation: each call bumps a generation, and every step checks it before running. When the
 * user jumps to a second album while the first is still loading, the first run stops issuing
 * requests, and `useFiles` drops any file response that belongs to an older load — so the screen
 * ends up showing the album the route names, never the one before.
 */
export function useAlbumLoader(deps: AlbumLoaderDeps): AlbumLoader {
  let generation = 0;
  let current: { albumId: number; presentation: boolean } | null = null;

  async function load(albumId: number, presentation: boolean): Promise<void> {
    const mine = ++generation;
    current = { albumId, presentation };
    const stale = () => mine !== generation;

    deps.clearEnabledAlbumTags();
    await deps.loadAlbumById(albumId, presentation);
    if (stale()) return;

    if (deps.isLoggedIn.value) {
      await deps.loadTags();
      if (stale()) return;
      if (!presentation) {
        await deps.loadEnabledAlbumTags(albumId);
        if (stale()) return;
      }
    }

    await deps.loadLanguageSettings();
    if (stale()) return;

    await deps.loadAlbumFiles(albumId, presentation);
    if (stale()) return;

    if (presentation) {
      await Promise.all([deps.loadRecordings(albumId), deps.loadGroups(albumId)]);
    }
  }

  async function reloadFiles(): Promise<void> {
    if (!current) return;
    await deps.loadAlbumFiles(current.albumId, current.presentation);
  }

  return { load, reloadFiles };
}
