// RED step #4: drive out config parsing + validation with helpful errors.
import { describe, expect, it } from "bun:test";
import { parseConfig } from "../src/config.ts";

describe("parseConfig", () => {
  it("parses a valid config string into a typed SecretConfig", () => {
    const raw = JSON.stringify({
      secrets: [
        { name: "API_KEY", lastRotated: "2026-01-01", rotationPolicyDays: 90, requiredBy: ["api"] },
      ],
    });
    const config = parseConfig(raw);
    expect(config.secrets).toHaveLength(1);
    expect(config.secrets[0]!.name).toBe("API_KEY");
  });

  it("throws a clear error on invalid JSON", () => {
    expect(() => parseConfig("{not json")).toThrow(/Failed to parse config JSON/);
  });

  it("throws when the top-level shape is wrong", () => {
    expect(() => parseConfig(JSON.stringify({ foo: 1 }))).toThrow(/must have a "secrets" array/);
  });

  it("throws when a secret is missing a required field", () => {
    const raw = JSON.stringify({ secrets: [{ name: "X", lastRotated: "2026-01-01" }] });
    expect(() => parseConfig(raw)).toThrow(/rotationPolicyDays/);
  });

  it("throws when requiredBy is not an array of strings", () => {
    const raw = JSON.stringify({
      secrets: [{ name: "X", lastRotated: "2026-01-01", rotationPolicyDays: 30, requiredBy: "api" }],
    });
    expect(() => parseConfig(raw)).toThrow(/requiredBy/);
  });

  it("rejects a non-positive rotation policy", () => {
    const raw = JSON.stringify({
      secrets: [{ name: "X", lastRotated: "2026-01-01", rotationPolicyDays: 0, requiredBy: [] }],
    });
    expect(() => parseConfig(raw)).toThrow(/positive/);
  });
});
