import { ref, type Ref } from "vue";
import { useApi } from "./useApi";

export interface SettingsComposable {
  language1Name: Ref<string>;
  language2Name: Ref<string>;
  targetAlbumId: Ref<number | null>;
  loadLanguageSettings: () => Promise<void>;
  updateLanguage1Name: (newName: string) => Promise<void>;
  updateLanguage2Name: (newName: string) => Promise<void>;
  loadTargetAlbum: () => Promise<void>;
  updateTargetAlbum: (albumId: number) => Promise<void>;
}

/**
 * Settings composable for managing app settings
 */
export function useSettings(): SettingsComposable {
  const { apiUrl, fetchWithAuth } = useApi();

  const language1Name = ref<string>("German");
  const language2Name = ref<string>("English");
  const targetAlbumId = ref<number | null>(null);

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

  return {
    // State
    language1Name,
    language2Name,
    targetAlbumId,

    // Methods
    loadLanguageSettings,
    updateLanguage1Name,
    updateLanguage2Name,
    loadTargetAlbum,
    updateTargetAlbum,
  };
}
