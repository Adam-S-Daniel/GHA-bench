// TDD: tests for parsing/validating the secret configuration input.
import { describe, expect, test } from "bun:test";
import { parseConfig } from "../src/config";

describe("parseConfig", () => {
  test("parses a valid config (array form)", () => {
    const json = JSON.stringify([
      {
        name: "a",
        lastRotated: "2026-01-01",
        rotationPolicyDays: 30,
        requiredBy: ["x"],
      },
    ]);
    const secrets = parseConfig(json);
    expect(secrets).toHaveLength(1);
    expect(secrets[0]!.name).toBe("a");
  });

  test("parses a valid config (object with `secrets` key)", () => {
    const json = JSON.stringify({
      secrets: [
        { name: "a", lastRotated: "2026-01-01", rotationPolicyDays: 30, requiredBy: [] },
      ],
    });
    const secrets = parseConfig(json);
    expect(secrets).toHaveLength(1);
  });

  test("defaults requiredBy to an empty array when omitted", () => {
    const json = JSON.stringify([
      { name: "a", lastRotated: "2026-01-01", rotationPolicyDays: 30 },
    ]);
    const secrets = parseConfig(json);
    expect(secrets[0]!.requiredBy).toEqual([]);
  });

  test("throws a meaningful error on malformed JSON", () => {
    expect(() => parseConfig("{not json")).toThrow(/failed to parse/i);
  });

  test("throws when a secret is missing a name", () => {
    const json = JSON.stringify([
      { lastRotated: "2026-01-01", rotationPolicyDays: 30 },
    ]);
    expect(() => parseConfig(json)).toThrow(/name/i);
  });

  test("throws when rotationPolicyDays is missing or not a number", () => {
    const json = JSON.stringify([
      { name: "a", lastRotated: "2026-01-01", rotationPolicyDays: "thirty" },
    ]);
    expect(() => parseConfig(json)).toThrow(/rotationPolicyDays/i);
  });

  test("throws when the top-level value is neither array nor {secrets}", () => {
    expect(() => parseConfig(JSON.stringify({ foo: 1 }))).toThrow(/array|secrets/i);
  });
});
