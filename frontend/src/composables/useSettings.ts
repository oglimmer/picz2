import { ref, type Ref } from "vue";
import { useApi } from "./useApi";

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

// Shared across every caller (same pattern as useAuth): the albums masthead shows the
// upload destination while other components change it, so both must read one ref.
const language1Name = ref<string>("German");
const language2Name = ref<string>("English");
const targetAlbumId = ref<number | null>(null);
// Safe until proven otherwise: if the load fails we would rather draw "new photos stay hidden"
// than tell the user their album is closed while it is open.
const newAssetTag = ref<NewAssetTag>("hidden");

/**
 * Settings composable for managing app settings
 */
export function useSettings(): SettingsComposable {
  const { apiUrl, fetchWithAuth } = useApi();

  /**
   * Load language settings
   */
  async function loadLanguageSettings(): Promise<void> {
    try {
      const response = await fetchWithAuth(`${apiUrl}/api/settings/languages`);
      const data = await response.json();

      if (data.success) {
        language1Name.value = data.language1 || "German";
        language2Name.value = data.language2 || "English";
      }
    } catch (err) {
      console.error("Error loading language settings:", err);
    }
  }

  /**
   * Update language 1 name
   */
  async function updateLanguage1Name(newName: string): Promise<void> {
    if (!newName || newName.trim() === "") {
      throw new Error("Language name cannot be empty");
    }

    try {
      const response = await fetchWithAuth(
        `${apiUrl}/api/settings/languages/1`,
        {
          method: "PUT",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ value: newName }),
        },
      );

      const data = await response.json();

      if (response.ok && data.success) {
        language1Name.value = newName;
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error saving language 1 name:", err);
      throw err;
    }
  }

  /**
   * Update language 2 name
   */
  async function updateLanguage2Name(newName: string): Promise<void> {
    if (!newName || newName.trim() === "") {
      throw new Error("Language name cannot be empty");
    }

    try {
      const response = await fetchWithAuth(
        `${apiUrl}/api/settings/languages/2`,
        {
          method: "PUT",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ value: newName }),
        },
      );

      const data = await response.json();

      if (response.ok && data.success) {
        language2Name.value = newName;
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error saving language 2 name:", err);
      throw err;
    }
  }

  /**
   * Load target album setting
   */
  async function loadTargetAlbum(): Promise<void> {
    try {
      const response = await fetchWithAuth(
        `${apiUrl}/api/settings/target-album`,
      );
      const data = await response.json();

      if (data.success) {
        targetAlbumId.value = data.albumId || null;
      }
    } catch (err) {
      console.error("Error loading target album:", err);
    }
  }

  /**
   * Update target album
   */
  async function updateTargetAlbum(albumId: number): Promise<void> {
    if (!albumId) {
      throw new Error("Album ID is required");
    }

    try {
      const response = await fetchWithAuth(
        `${apiUrl}/api/settings/target-album`,
        {
          method: "PUT",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ albumId }),
        },
      );

      const data = await response.json();

      if (response.ok && data.success) {
        targetAlbumId.value = albumId;
      } else {
        throw new Error(data.message || "Unknown error");
      }
    } catch (err) {
      console.error("Error saving target album:", err);
      throw err;
    }
  }

  /**
   * Clear the target album — the iOS app stops uploading until one is picked again.
   */
  async function clearTargetAlbum(): Promise<void> {
    const response = await fetchWithAuth(`${apiUrl}/api/settings/target-album`, {
      method: "DELETE",
    });

    const data = await response.json();

    if (!response.ok || !data.success) {
      throw new Error(data.message || "Failed to pause uploads");
    }

    targetAlbumId.value = null;
  }

  /**
   * Load which tag new uploads get.
   */
  async function loadNewAssetTag(): Promise<void> {
    try {
      const response = await fetchWithAuth(
        `${apiUrl}/api/settings/new-asset-tag`,
      );
      const data = await response.json();

      if (data.success && data.tagName) {
        newAssetTag.value = data.tagName as NewAssetTag;
      }
    } catch (err) {
      console.error("Error loading new-asset tag:", err);
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
    const response = await fetchWithAuth(
      `${apiUrl}/api/settings/new-asset-tag`,
      {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ tagName, confirmed: true }),
      },
    );

    const data = await response.json();

    if (!response.ok || !data.success) {
      throw new Error(data.message || "Failed to save the setting");
    }

    newAssetTag.value = data.tagName as NewAssetTag;
  }

  return {
    // State
    language1Name,
    language2Name,
    targetAlbumId,
    newAssetTag,

    // Methods
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
