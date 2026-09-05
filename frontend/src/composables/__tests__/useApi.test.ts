import { describe, expect, it, vi } from "vitest";
import { ApiError, jsonBody, useApi } from "../useApi";

function answer(status: number, body: string, contentType = "application/json"): Response {
  return new Response(body, { status, headers: { "Content-Type": contentType } });
}

describe("requestPublicJson / requestJson", () => {
  it("returns the parsed body on a 2xx", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(answer(200, '{"success":true,"albums":[1]}')));
    const { requestPublicJson } = useApi();
    await expect(requestPublicJson("http://x/api/albums")).resolves.toEqual({ success: true, albums: [1] });
  });

  it("throws the server's sentence on a non-2xx, with the status attached", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(answer(409, '{"success":false,"message":"Name taken"}')));
    const { requestPublicJson } = useApi();
    const err: unknown = await requestPublicJson("http://x/api/albums").catch((e) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect((err as ApiError).message).toBe("Name taken");
    expect((err as ApiError).status).toBe(409);
  });

  it("treats a 200 that says success:false as a failure too", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(answer(200, '{"success":false,"message":"Nope"}')));
    const { requestPublicJson } = useApi();
    await expect(requestPublicJson("http://x/y")).rejects.toThrow("Nope");
  });

  it("turns a non-JSON body (Spring's plain 401, a gateway's HTML) into a status message", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(answer(401, "Unauthorized", "text/plain")));
    const { requestPublicJson } = useApi();
    await expect(requestPublicJson("http://x/y")).rejects.toThrow("Request failed (HTTP 401)");
  });

  it("also reads the storage endpoints' `error` field", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(answer(400, '{"error":"Bucket missing"}')));
    const { requestPublicJson } = useApi();
    await expect(requestPublicJson("http://x/y")).rejects.toThrow("Bucket missing");
  });

  it("does not send credentials on the public variant, and does on the authenticated one", async () => {
    const fetchMock = vi.fn().mockResolvedValue(answer(200, "{}"));
    vi.stubGlobal("fetch", fetchMock);
    const { requestPublicJson, requestJson } = useApi();
    await requestPublicJson("http://x/public");
    await requestJson("http://x/private", jsonBody("POST", { a: 1 }));
    expect(fetchMock).toHaveBeenCalledTimes(2);
    const [, privateInit] = fetchMock.mock.calls[1];
    expect(privateInit.method).toBe("POST");
    expect(privateInit.body).toBe('{"a":1}');
    expect(privateInit.headers["Content-Type"]).toBe("application/json");
    // Signed out in this test, so no Authorization header either way.
    expect(privateInit.headers.Authorization).toBeUndefined();
  });
});
