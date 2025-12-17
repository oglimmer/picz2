import { ref, type Ref } from "vue";
import { useApi } from "./useApi";

export interface AnalyticsStats {
  totalEvents: number;
  uniqueVisitors: number;
  pageViews: number;
  filterChanges: number;
  audioPlays: number;
  filterTagCounts: Record<string, number>;
}

export interface AnalyticsComposable {
  visitorId: Ref<string>;
  hasConsent: Ref<boolean>;
  consentGiven: (accepted: boolean) => void;
  getAlbumStatistics: (albumId: number) => Promise<AnalyticsStats>;
  logPageView: (shareToken: string, tag?: string) => Promise<void>;
  logFilterChange: (shareToken: string, tag: string) => Promise<void>;
  logAudioPlay: (shareToken: string, recordingId: number, tag?: string) => Promise<void>;
}

const VISITOR_ID_COOKIE = "visitor_id";
const CONSENT_COOKIE = "cookie_consent";
const COOKIE_MAX_AGE_DAYS = 90; // 3 months

/**
 * Analytics composable for managing visitor ID and retrieving statistics
 * GDPR Compliance:
 * - Analytics events are always tracked (page views, filter changes, audio plays)
 * - visitor_id cookie is only set if user gives consent (accept banner)
 * - Without consent: events logged with IP/user-agent only (no persistent visitor_id)
 * - With consent: events logged with persistent visitor_id cookie for returning visitor tracking
 */
export function useAnalytics(): AnalyticsComposable {
  const { apiUrl, fetchWithAuth } = useApi();
  const visitorId = ref<string>("");
  const hasConsent = ref<boolean>(false);

  // Check consent status on initialization
  hasConsent.value = checkConsentStatus();

  /**
   * Check if user has given consent for analytics cookies
   */
  function checkConsentStatus(): boolean {
    const cookies = document.cookie.split(";");
    for (const cookie of cookies) {
      const [name, value] = cookie.trim().split("=");
      if (name === CONSENT_COOKIE) {
        return value === "accepted";
      }
    }
    return false;
  }

  /**
   * Called when user makes a consent choice
   * If accepted, sets the visitor ID cookie
   */
  function consentGiven(accepted: boolean): void {
    hasConsent.value = accepted;

    if (accepted) {
      // User accepted - set visitor ID cookie
      setVisitorIdCookie();
    } else {
      // User declined - remove visitor ID cookie if it exists
      removeVisitorIdCookie();
    }
  }

  /**
   * Set visitor ID cookie (only if consent was given)
   */
  function setVisitorIdCookie(): void {
    // Try to get existing cookie first
    const cookies = document.cookie.split(";");
    for (const cookie of cookies) {
      const [name, value] = cookie.trim().split("=");
      if (name === VISITOR_ID_COOKIE) {
        visitorId.value = value;
        return;
      }
    }

    // Generate new visitor ID
    const newVisitorId = generateVisitorId();
    visitorId.value = newVisitorId;

    // Set cookie with 3-month expiration
    const expiryDate = new Date();
    expiryDate.setDate(expiryDate.getDate() + COOKIE_MAX_AGE_DAYS);
    document.cookie = `${VISITOR_ID_COOKIE}=${newVisitorId}; expires=${expiryDate.toUTCString()}; path=/; SameSite=Lax; Secure`;
  }

  /**
   * Remove visitor ID cookie
   */
  function removeVisitorIdCookie(): void {
    visitorId.value = "";
    // Set cookie to expire immediately
    document.cookie = `${VISITOR_ID_COOKIE}=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/; SameSite=Lax; Secure`;
  }

  /**
   * Generate a random visitor ID
   */
  function generateVisitorId(): string {
    const timestamp = Date.now().toString(36);
    const randomPart = Math.random().toString(36).substring(2, 15);
    return `${timestamp}-${randomPart}`;
  }

  /**
   * Get analytics statistics for an album
   */
  async function getAlbumStatistics(albumId: number): Promise<AnalyticsStats> {
    try {
      const response = await fetchWithAuth(
        `${apiUrl}/api/albums/${albumId}/analytics`
      );
      const data = await response.json();

      if (data.success) {
        return {
          totalEvents: data.totalEvents || 0,
          uniqueVisitors: data.uniqueVisitors || 0,
          pageViews: data.pageViews || 0,
          filterChanges: data.filterChanges || 0,
          audioPlays: data.audioPlays || 0,
          filterTagCounts: data.filterTagCounts || {},
        };
      } else {
        throw new Error(data.message || "Failed to fetch analytics");
      }
    } catch (err) {
      console.error("Error fetching album statistics:", err);
      throw err;
    }
  }

  /**
   * Log page view event
   * Always tracks analytics, but only uses visitor_id cookie if consent given
   */
  async function logPageView(shareToken: string, tag?: string): Promise<void> {
    try {
      const url = tag
        ? `${apiUrl}/api/albums/public/${shareToken}/analytics/page-view?tag=${encodeURIComponent(tag)}`
        : `${apiUrl}/api/albums/public/${shareToken}/analytics/page-view`;

      await fetch(url, {
        method: 'POST',
        credentials: 'include' // Include cookies in the request
      });
    } catch (err) {
      console.error("Error logging page view:", err);
      // Silently fail - analytics errors shouldn't break the app
    }
  }

  /**
   * Log filter change event
   * Always tracks analytics, but only uses visitor_id cookie if consent given
   */
  async function logFilterChange(shareToken: string, tag: string): Promise<void> {
    try {
      const url = `${apiUrl}/api/albums/public/${shareToken}/analytics/filter-change?tag=${encodeURIComponent(tag)}`;
      await fetch(url, {
        method: 'POST',
        credentials: 'include' // Include cookies in the request
      });
    } catch (err) {
      console.error("Error logging filter change:", err);
      // Silently fail - analytics errors shouldn't break the app
    }
  }

  /**
   * Log audio play event
   * Always tracks analytics, but only uses visitor_id cookie if consent given
   */
  async function logAudioPlay(shareToken: string, recordingId: number, tag?: string): Promise<void> {
    try {
      const url = tag
        ? `${apiUrl}/api/albums/public/${shareToken}/analytics/audio-play?recordingId=${recordingId}&tag=${encodeURIComponent(tag)}`
        : `${apiUrl}/api/albums/public/${shareToken}/analytics/audio-play?recordingId=${recordingId}`;

      await fetch(url, {
        method: 'POST',
        credentials: 'include' // Include cookies in the request
      });
    } catch (err) {
      console.error("Error logging audio play:", err);
      // Silently fail - analytics errors shouldn't break the app
    }
  }

  return {
    visitorId,
    hasConsent,
    consentGiven,
    getAlbumStatistics,
    logPageView,
    logFilterChange,
    logAudioPlay,
  };
}
