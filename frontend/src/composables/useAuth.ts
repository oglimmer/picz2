import { ref, type Ref } from "vue";
import { getApiUrl } from "../utils/api-config";
import { basicAuthHeader } from "../utils/basicAuth";

const apiUrl = getApiUrl();

const EMAIL_KEY = "authEmail";
const TOKEN_KEY = "authToken";
/**
 * Where the plaintext password used to live before D78. Read once on start-up to trade it for a
 * session, then deleted — so an already-signed-in browser stays signed in through the upgrade and
 * stops holding the password on the same visit.
 */
const LEGACY_PASSWORD_KEY = "authPassword";

// Shared auth state across the app (module singleton — see composables/README.md).
const authEmail = ref<string>("");
const sessionToken = ref<string>("");
const isLoggedIn = ref<boolean>(false);
const emailVerified = ref<boolean>(false);
// Operator account (users.is_admin). Gates controls that answer 403 for everyone else, such as
// renaming the narration languages.
const isAdmin = ref<boolean>(false);
const loginError = ref<string>("");

interface SessionResponse {
  token: string;
  expiresAt: string;
  expiresInSeconds: number;
  email: string;
  emailVerified: boolean;
  admin: boolean;
}

interface AuthCheckResponse {
  success: boolean;
  email: string;
  emailVerified: boolean;
  admin: boolean;
}

export interface AuthComposable {
  authEmail: Ref<string>;
  isLoggedIn: Ref<boolean>;
  emailVerified: Ref<boolean>;
  isAdmin: Ref<boolean>;
  loginError: Ref<string>;
  login: (email: string, password: string) => Promise<boolean>;
  logout: () => void;
  initAuth: () => Promise<boolean>;
  getAuthHeaders: () => Record<string, string>;
}

function applyAccount(account: { email: string; emailVerified: boolean; admin: boolean }): void {
  authEmail.value = account.email;
  emailVerified.value = account.emailVerified === true;
  isAdmin.value = account.admin === true;
}

function clearSession(): void {
  authEmail.value = "";
  sessionToken.value = "";
  isLoggedIn.value = false;
  emailVerified.value = false;
  isAdmin.value = false;
  localStorage.removeItem(EMAIL_KEY);
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(LEGACY_PASSWORD_KEY);
}

/**
 * Trades a password for a session token (D78). The password crosses the wire exactly here, as
 * Basic auth on one request, and is never kept. `null` means the server said no; a network
 * failure throws so the caller can tell the two apart.
 */
async function createSession(email: string, password: string): Promise<SessionResponse | null> {
  const res = await fetch(`${apiUrl}/api/auth/sessions`, {
    method: "POST",
    headers: { Authorization: basicAuthHeader(email, password) },
  });
  if (!res.ok) return null;
  const data = (await res.json().catch(() => null)) as SessionResponse | null;
  return data && typeof data.token === "string" && data.token ? data : null;
}

function storeSession(session: SessionResponse): void {
  sessionToken.value = session.token;
  applyAccount(session);
  isLoggedIn.value = true;
  localStorage.setItem(EMAIL_KEY, session.email);
  localStorage.setItem(TOKEN_KEY, session.token);
}

/**
 * Authentication composable.
 *
 * <p>The browser holds a revocable session token, not the account password (D78). The token is
 * sent as `Authorization: Bearer` on every call, dies on logout and on any password change, and a
 * 401 anywhere means "sign in again". iOS keeps using Basic; the server accepts both.
 */
export function useAuth(): AuthComposable {
  /**
   * Login with email and password
   */
  async function login(email: string, password: string): Promise<boolean> {
    loginError.value = "";

    if (!email || !password) {
      loginError.value = "Email and password are required";
      return false;
    }

    try {
      const session = await createSession(email, password);
      if (!session) {
        loginError.value = "Invalid email or password";
        return false;
      }
      storeSession(session);
      return true;
    } catch {
      loginError.value = "Could not reach the server. Try again.";
      return false;
    }
  }

  /**
   * Logout: tell the server to forget this session, then forget it here. The request is fire and
   * forget — a browser that is already offline still has to end up logged out.
   */
  function logout(): void {
    const token = sessionToken.value;
    if (token) {
      fetch(`${apiUrl}/api/auth/sessions/current`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` },
      }).catch(() => {
        // Nothing to do: the token expires on its own.
      });
    }
    clearSession();
    loginError.value = "";
  }

  /**
   * Restores the session on start-up.
   *
   * <p>A stored token is checked against `/api/auth/check`. A 401 or 403 means it was revoked or
   * expired, so it is dropped. Any other failure (server down, offline) keeps the token for the
   * next start but reports "not logged in" for this one, exactly as before.
   *
   * <p>A browser still holding the pre-D78 password trades it for a token once, then loses it.
   */
  async function initAuth(): Promise<boolean> {
    const legacyEmail = localStorage.getItem(EMAIL_KEY);
    const legacyPassword = localStorage.getItem(LEGACY_PASSWORD_KEY);
    if (legacyPassword) {
      localStorage.removeItem(LEGACY_PASSWORD_KEY);
      if (legacyEmail) {
        try {
          const session = await createSession(legacyEmail, legacyPassword);
          if (session) {
            storeSession(session);
            return true;
          }
        } catch {
          // Fall through: no token, so the user simply signs in again.
        }
      }
    }

    const savedToken = localStorage.getItem(TOKEN_KEY);
    if (!savedToken) return false;

    try {
      const res = await fetch(`${apiUrl}/api/auth/check`, {
        headers: { Authorization: `Bearer ${savedToken}` },
      });
      if (res.status === 401 || res.status === 403) {
        clearSession();
        return false;
      }
      if (!res.ok) return false;
      const data = (await res.json().catch(() => null)) as AuthCheckResponse | null;
      if (!data || data.success !== true) return false;
      sessionToken.value = savedToken;
      applyAccount(data);
      isLoggedIn.value = true;
      return true;
    } catch {
      return false;
    }
  }

  /**
   * The Authorization header for API calls, or nothing when signed out.
   */
  function getAuthHeaders(): Record<string, string> {
    if (!isLoggedIn.value || !sessionToken.value) {
      return {};
    }
    return { Authorization: `Bearer ${sessionToken.value}` };
  }

  return {
    // State
    authEmail,
    isLoggedIn,
    emailVerified,
    isAdmin,
    loginError,

    // Methods
    login,
    logout,
    initAuth,
    getAuthHeaders,
  };
}
