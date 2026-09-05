/** The value of one cookie, or null when the browser holds none by that name. */
export function readCookie(name: string): string | null {
  for (const part of document.cookie.split(";")) {
    const eq = part.indexOf("=");
    const key = (eq < 0 ? part : part.slice(0, eq)).trim();
    if (key === name) return eq < 0 ? "" : part.slice(eq + 1).trim();
  }
  return null;
}

/**
 * Sets a cookie for `days` days (or expires it at once when `days` is 0). `Secure` is only sent
 * on https: on a plain-http dev host other than localhost the browser would drop a Secure cookie
 * silently, and the consent banner would come back on every visit.
 */
export function writeCookie(name: string, value: string, days: number): void {
  const expires = new Date();
  expires.setDate(expires.getDate() + days);
  const secure = window.location.protocol === "https:" ? "; Secure" : "";
  document.cookie = `${name}=${value}; expires=${expires.toUTCString()}; path=/; SameSite=Lax${secure}`;
}
