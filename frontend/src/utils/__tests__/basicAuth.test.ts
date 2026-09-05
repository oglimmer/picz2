import { describe, expect, it } from "vitest";
import { base64Utf8, basicAuthHeader } from "../basicAuth";

function decode(header: string): string {
  const b64 = header.replace(/^Basic /, "");
  return new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)));
}

describe("basicAuthHeader", () => {
  it("round-trips ASCII credentials", () => {
    expect(decode(basicAuthHeader("a@b.de", "hunter2"))).toBe("a@b.de:hunter2");
  });

  it("round-trips every Unicode range btoa alone would break or mangle", () => {
    // "ü" is Latin-1 (btoa accepts it but as one byte, not UTF-8); "€" and the emoji are beyond
    // U+00FF and make bare btoa throw.
    const password = "pä€😀 Пароль 密码";
    expect(decode(basicAuthHeader("a@b.de", password))).toBe(`a@b.de:${password}`);
  });

  it("produces what the server's UTF-8 Basic decoder expects for a Latin-1 character", () => {
    // UTF-8 for "ü" is C3 BC; a raw btoa would have encoded the single byte FC.
    expect(base64Utf8("ü")).toBe("w7w=");
  });
});
