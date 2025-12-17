import { ref, type Ref } from "vue";
import { getApiUrl } from "../utils/api-config";

const apiUrl = getApiUrl();

// Shared auth state across the app
const authEmail = ref<string>("");
const authPassword = ref<string>("");
const isLoggedIn = ref<boolean>(false);
const emailVerified = ref<boolean>(false);
const loginError = ref<string>("");

export interface AuthComposable {
  authEmail: Ref<string>;
  authPassword: Ref<string>;
  isLoggedIn: Ref<boolean>;
  emailVerified: Ref<boolean>;
  loginError: Ref<string>;
  login: () => Promise<boolean>;
  logout: () => void;
  initAuth: () => Promise<boolean>;
  verifyCredentials: (email: string, password: string) => Promise<boolean>;
  getAuthHeaders: () => Record<string, string>;
}

/**
 * Authentication composable for managing user login state
 */
export function useAuth(): AuthComposable {
  /**
   * Verify credentials with the server
   */
  async function verifyCredentials(
    email: string,
    password: string,
  ): Promise<boolean> {
    try {
      const token = btoa(`${email}:${password}`);
      const res = await fetch(`${apiUrl}/api/auth/check`, {
        headers: { Authorization: `Basic ${token}` },
      });
      if (!res.ok) return false;
      const data = await res.json().catch(() => ({}));
      if (data && data.success === true) {
        emailVerified.value = data.emailVerified || false;
        return true;
      }
      return false;
    } catch {
      return false;
    }
  }

  /**
   * Login with email and password
   */
  async function login(): Promise<boolean> {
    loginError.value = "";

    if (!authEmail.value || !authPassword.value) {
      loginError.value = "Email and password are required";
      return false;
    }

    const ok = await verifyCredentials(authEmail.value, authPassword.value);

    if (!ok) {
      loginError.value = "Invalid email or password";
      return false;
    }

    localStorage.setItem("authEmail", authEmail.value);
    localStorage.setItem("authPassword", authPassword.value);
    isLoggedIn.value = true;
    return true;
  }

  /**
   * Logout and clear credentials
   */
  function logout(): void {
    authEmail.value = "";
    authPassword.value = "";
    localStorage.removeItem("authEmail");
    localStorage.removeItem("authPassword");
    isLoggedIn.value = false;
    emailVerified.value = false;
    loginError.value = "";
  }

  /**
   * Initialize auth from localStorage
   */
  async function initAuth(): Promise<boolean> {
    const savedEmail = localStorage.getItem("authEmail");
    const savedPassword = localStorage.getItem("authPassword");

    if (savedEmail && savedPassword) {
      const ok = await verifyCredentials(savedEmail, savedPassword);
      if (ok) {
        authEmail.value = savedEmail;
        authPassword.value = savedPassword;
        isLoggedIn.value = true;
        return true;
      }
    }
    return false;
  }

  /**
   * Get Basic Auth header
   */
  function getAuthHeaders(): Record<string, string> {
    if (!isLoggedIn.value || !authEmail.value || !authPassword.value) {
      return {};
    }
    const token = btoa(`${authEmail.value}:${authPassword.value}`);
    return { Authorization: `Basic ${token}` };
  }

  return {
    // State
    authEmail,
    authPassword,
    isLoggedIn,
    emailVerified,
    loginError,

    // Methods
    login,
    logout,
    initAuth,
    verifyCredentials,
    getAuthHeaders,
  };
}
