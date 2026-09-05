import { describe, expect, it, vi } from "vitest";
import { ref } from "vue";
import { useAlbumLoader } from "../useAlbumLoader";

/** A promise the test resolves by hand, to interleave two loads. */
function gate() {
  let open!: () => void;
  const promise = new Promise<void>((resolve) => (open = resolve));
  return { promise, open };
}

function deps(loadAlbumById: (id: number) => Promise<unknown>) {
  return {
    isLoggedIn: ref(true),
    loadAlbumById: vi.fn(loadAlbumById),
    loadAlbumFiles: vi.fn(async () => {}),
    loadTags: vi.fn(async () => {}),
    loadEnabledAlbumTags: vi.fn(async () => {}),
    clearEnabledAlbumTags: vi.fn(),
    loadLanguageSettings: vi.fn(async () => {}),
    loadRecordings: vi.fn(async () => {}),
    loadGroups: vi.fn(async () => {}),
  };
}

describe("useAlbumLoader", () => {
  it("loads in order and only fetches recordings and groups for a presentation", async () => {
    const d = deps(async () => ({}));
    const loader = useAlbumLoader(d);
    await loader.load(5, false);
    expect(d.loadEnabledAlbumTags).toHaveBeenCalledWith(5);
    expect(d.loadAlbumFiles).toHaveBeenCalledWith(5, false);
    expect(d.loadRecordings).not.toHaveBeenCalled();

    await loader.load(5, true);
    expect(d.loadRecordings).toHaveBeenCalledWith(5);
    expect(d.loadGroups).toHaveBeenCalledWith(5);
    // Presentation mode has no tag picker, so its enabled tags are not asked for again.
    expect(d.loadEnabledAlbumTags).toHaveBeenCalledTimes(1);
  });

  it("a newer load cancels the rest of an older one", async () => {
    const first = gate();
    const d = deps(async (id) => {
      if (id === 1) await first.promise;
      return {};
    });
    const loader = useAlbumLoader(d);

    const older = loader.load(1, false);
    await loader.load(2, false); // completes while album 1 is still waiting
    first.open();
    await older;

    // Album 1's later steps never ran: files were only fetched for album 2.
    expect(d.loadAlbumFiles).toHaveBeenCalledTimes(1);
    expect(d.loadAlbumFiles).toHaveBeenCalledWith(2, false);
  });

  it("reloadFiles re-fetches the album loaded last", async () => {
    const d = deps(async () => ({}));
    const loader = useAlbumLoader(d);
    await loader.reloadFiles(); // nothing loaded yet: no call
    expect(d.loadAlbumFiles).not.toHaveBeenCalled();
    await loader.load(3, true);
    await loader.reloadFiles();
    expect(d.loadAlbumFiles).toHaveBeenLastCalledWith(3, true);
  });
});
