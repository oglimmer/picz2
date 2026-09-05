import { ref, type Ref } from "vue";
import { useApi } from "./useApi";
import { readCookie, writeCookie } from "../utils/cookies";

export interface AnalyticsStats {
  analyticsPaused: boolean;
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
  resetAlbumAnalytics: (albumId: number) => Promise<void>;
  setAnalyticsPaused: (albumId: number, paused: boolean) => Promise<void>;
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
  const { apiUrl, requestJson } = useApi();
  const visitorId = ref<string>("");
  const hasConsent = ref<boolean>(false);

  // Check consent status on initialization
  hasConsent.value = checkConsentStatus();

  /**
   * Check if user has given consent for analytics cookies
   */
  function checkConsentStatus(): boolean {
    return readCookie(CONSENT_COOKIE) === "accepted";
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
    const existing = readCookie(VISITOR_ID_COOKIE);
    if (existing) {
      visitorId.value = existing;
      return;
    }

    // Generate new visitor ID
    const newVisitorId = generateVisitorId();
    visitorId.value = newVisitorId;

    // Set cookie with 3-month expiration
    writeCookie(VISITOR_ID_COOKIE, newVisitorId, COOKIE_MAX_AGE_DAYS);
  }

  /**
   * Remove visitor ID cookie
   */
  function removeVisitorIdCookie(): void {
    visitorId.value = "";
    // Set cookie to expire immediately
    writeCookie(VISITOR_ID_COOKIE, "", -1);
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
    const data = await requestJson<Partial<AnalyticsStats>>(
      `${apiUrl}/api/albums/${albumId}/analytics`,
    );
    return {
      analyticsPaused: data.analyticsPaused || false,
      totalEvents: data.totalEvents || 0,
      uniqueVisitors: data.uniqueVisitors || 0,
      pageViews: data.pageViews || 0,
      filterChanges: data.filterChanges || 0,
      audioPlays: data.audioPlays || 0,
      filterTagCounts: data.filterTagCounts || {},
    };
  }

  async function resetAlbumAnalytics(albumId: number): Promise<void> {
    await requestJson(`${apiUrl}/api/albums/${albumId}/analytics`, { method: "DELETE" });
  }

  async function setAnalyticsPaused(albumId: number, paused: boolean): Promise<void> {
    await requestJson(`${apiUrl}/api/albums/${albumId}/analytics/paused?paused=${paused}`, {
      method: "PUT",
    });
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
    } catch {
      // Analytics must never break the page.
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
    } catch {
      // Analytics must never break the page.
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
    } catch {
      // Analytics must never break the page.
    }
  }

  return {
    visitorId,
    hasConsent,
    consentGiven,
    getAlbumStatistics,
    resetAlbumAnalytics,
    setAnalyticsPaused,
    logPageView,
    logFilterChange,
    logAudioPlay,
  };
}
