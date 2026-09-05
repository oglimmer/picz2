import { ref, type Ref } from "vue";
import { useApi, jsonBody } from "./useApi";

/**
 * The tag every newly uploaded photo or video gets (D70).
 *
 * `"hidden"` is the holding pen: the server strips those assets out of every public listing, so a
 * published album shows nothing new until the owner has looked at it. `"all"` is the older
 * behaviour — visible the moment processing finishes.
 */
export type NewAssetTag = "hidden" | "all";

export interface SettingsComposable {
  language1Name: Ref<string>;
  language2Name: Ref<string>;
  targetAlbumId: Ref<number | null>;
  newAssetTag: Ref<NewAssetTag>;
  loadLanguageSettings: () => Promise<void>;
  updateLanguage1Name: (newName: string) => Promise<void>;
  updateLanguage2Name: (newName: string) => Promise<void>;
  loadTargetAlbum: () => Promise<void>;
  updateTargetAlbum: (albumId: number) => Promise<void>;
  clearTargetAlbum: () => Promise<void>;
  loadNewAssetTag: () => Promise<void>;
  updateNewAssetTag: (tagName: NewAssetTag) => Promise<void>;
}

// Module singleton (see README.md): the albums masthead shows the upload destination while other
// components change it, so both must read one ref.
const language1Name = ref<string>("German");
const language2Name = ref<string>("English");
const targetAlbumId = ref<number | null>(null);
// Safe until proven otherwise: if the load fails we would rather draw "new photos stay hidden"
// than tell the user their album is closed while it is open.
const newAssetTag = ref<NewAssetTag>("hidden");

export function useSettings(): SettingsComposable {
  const { apiUrl, requestJson } = useApi();

  /** Non-fatal: the defaults stand if the server cannot be asked. */
  async function loadLanguageSettings(): Promise<void> {
    try {
      const data = await requestJson<{ language1?: string; language2?: string }>(
        `${apiUrl}/api/settings/languages`,
      );
      language1Name.value = data.language1 || "German";
      language2Name.value = data.language2 || "English";
    } catch {
      // keep the defaults
    }
  }

  async function updateLanguageName(slot: 1 | 2, newName: string): Promise<void> {
    if (!newName || newName.trim() === "") {
      throw new Error("Language name cannot be empty");
    }
    await requestJson(`${apiUrl}/api/settings/languages/${slot}`, jsonBody("PUT", { value: newName }));
    (slot === 1 ? language1Name : language2Name).value = newName;
  }

  const updateLanguage1Name = (newName: string) => updateLanguageName(1, newName);
  const updateLanguage2Name = (newName: string) => updateLanguageName(2, newName);

  async function loadTargetAlbum(): Promise<void> {
    try {
      const data = await requestJson<{ albumId?: number | null }>(
        `${apiUrl}/api/settings/target-album`,
      );
      targetAlbumId.value = data.albumId || null;
    } catch {
      // leave whatever we had
    }
  }

  async function updateTargetAlbum(albumId: number): Promise<void> {
    if (!albumId) {
      throw new Error("Album ID is required");
    }
    await requestJson(`${apiUrl}/api/settings/target-album`, jsonBody("PUT", { albumId }));
    targetAlbumId.value = albumId;
  }

  /** Clear the target album — the iOS app stops uploading until one is picked again. */
  async function clearTargetAlbum(): Promise<void> {
    await requestJson(`${apiUrl}/api/settings/target-album`, { method: "DELETE" });
    targetAlbumId.value = null;
  }

  async function loadNewAssetTag(): Promise<void> {
    try {
      const data = await requestJson<{ tagName?: string }>(`${apiUrl}/api/settings/new-asset-tag`);
      if (data.tagName) newAssetTag.value = data.tagName as NewAssetTag;
    } catch {
      // keep "hidden", the safe default
    }
  }

  /**
   * Change it.
   *
   * `confirmed` is always sent as true because the caller is expected to have run its own
   * are-you-sure dialog first — the server rejects an unconfirmed switch to `"all"` outright, so
   * the flag is a handshake between the two, not a second UI state.
   */
  async function updateNewAssetTag(tagName: NewAssetTag): Promise<void> {
    const data = await requestJson<{ tagName?: string }>(
      `${apiUrl}/api/settings/new-asset-tag`,
      jsonBody("PUT", { tagName, confirmed: true }),
    );
    newAssetTag.value = (data.tagName as NewAssetTag) ?? tagName;
  }

  return {
    language1Name,
    language2Name,
    targetAlbumId,
    newAssetTag,
    loadLanguageSettings,
    updateLanguage1Name,
    updateLanguage2Name,
    loadTargetAlbum,
    updateTargetAlbum,
    clearTargetAlbum,
    loadNewAssetTag,
    updateNewAssetTag,
  };
}
