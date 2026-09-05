import { beforeEach, describe, expect, it, vi } from "vitest";
import { useAuth } from "../useAuth";

const SESSION = {
  token: "zst_abc",
  expiresAt: "2026-12-01T00:00:00Z",
  expiresInSeconds: 1000,
  email: "a@b.de",
  emailVerified: true,
  admin: false,
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

describe("useAuth (D78 session tokens)", () => {
  beforeEach(() => {
    localStorage.clear();
    useAuth().logout();
  });

  it("logs in with Basic once and keeps only the token", async () => {
    const fetchMock = vi.fn().mockResolvedValue(json(200, SESSION));
    vi.stubGlobal("fetch", fetchMock);
    const auth = useAuth();

    expect(await auth.login("a@b.de", "pä€")).toBe(true);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toMatch(/\/api\/auth\/sessions$/);
    expect(init.headers.Authorization).toMatch(/^Basic /);
    expect(auth.isLoggedIn.value).toBe(true);
    expect(auth.emailVerified.value).toBe(true);
    expect(auth.getAuthHeaders()).toEqual({ Authorization: "Bearer zst_abc" });
    expect(localStorage.getItem("authToken")).toBe("zst_abc");
    expect(localStorage.getItem("authPassword")).toBeNull();
    expect(Object.values(localStorage)).not.toContain("pä€");
  });

  it("reports wrong credentials and a dead server differently", async () => {
    const auth = useAuth();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json(401, {})));
    expect(await auth.login("a@b.de", "x")).toBe(false);
    expect(auth.loginError.value).toBe("Invalid email or password");

    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("Failed to fetch")));
    expect(await auth.login("a@b.de", "x")).toBe(false);
    expect(auth.loginError.value).toMatch(/reach the server/);
  });

  it("restores a stored session and drops a revoked one", async () => {
    localStorage.setItem("authToken", "zst_old");
    localStorage.setItem("authEmail", "a@b.de");
    const auth = useAuth();

    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(json(200, { success: true, email: "a@b.de", emailVerified: true, admin: true })),
    );
    expect(await auth.initAuth()).toBe(true);
    expect(auth.isAdmin.value).toBe(true);
    expect(auth.getAuthHeaders()).toEqual({ Authorization: "Bearer zst_old" });

    auth.logout();
    localStorage.setItem("authToken", "zst_old");
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json(401, {})));
    expect(await auth.initAuth()).toBe(false);
    expect(localStorage.getItem("authToken")).toBeNull();
  });

  it("keeps the token when the server is merely unreachable", async () => {
    localStorage.setItem("authToken", "zst_keep");
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("offline")));
    const auth = useAuth();
    expect(await auth.initAuth()).toBe(false);
    expect(localStorage.getItem("authToken")).toBe("zst_keep");
  });

  it("trades a pre-D78 stored password for a session and deletes the password", async () => {
    localStorage.setItem("authEmail", "a@b.de");
    localStorage.setItem("authPassword", "hunter2");
    const fetchMock = vi.fn().mockResolvedValue(json(200, SESSION));
    vi.stubGlobal("fetch", fetchMock);

    const auth = useAuth();
    expect(await auth.initAuth()).toBe(true);
    expect(fetchMock.mock.calls[0][0]).toMatch(/\/api\/auth\/sessions$/);
    expect(localStorage.getItem("authPassword")).toBeNull();
    expect(localStorage.getItem("authToken")).toBe("zst_abc");
  });

  it("logout tells the server and forgets everything locally even when that call fails", async () => {
    localStorage.setItem("authToken", "zst_abc");
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json(200, { success: true, email: "a@b.de" })));
    const auth = useAuth();
    await auth.initAuth();

    const fetchMock = vi.fn().mockRejectedValue(new TypeError("offline"));
    vi.stubGlobal("fetch", fetchMock);
    auth.logout();
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toMatch(/\/api\/auth\/sessions\/current$/);
    expect(init.method).toBe("DELETE");
    expect(auth.isLoggedIn.value).toBe(false);
    expect(localStorage.getItem("authToken")).toBeNull();
  });
});
