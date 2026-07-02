/**
 * TDD Cycle 2: config parsing/validation.
 *
 * parseConfig takes the raw JSON text of a secrets file and either returns a
 * validated SecretConfig[] or throws a ConfigError whose message pinpoints
 * exactly which entry/field is wrong — vague errors are useless in CI logs.
 */
import { describe, expect, test } from "bun:test";
import { ConfigError, parseConfig } from "../src/config";

const VALID = JSON.stringify([
  {
    name: "db-password",
    lastRotated: "2026-01-01",
    rotationPolicyDays: 90,
    requiredBy: ["auth-service"],
  },
]);

describe("parseConfig", () => {
  test("accepts a valid config", () => {
    const secrets = parseConfig(VALID);
    expect(secrets).toHaveLength(1);
    expect(secrets[0]!.name).toBe("db-password");
  });

  test("rejects malformed JSON with a helpful message", () => {
    expect(() => parseConfig("{ not json")).toThrow(ConfigError);
    expect(() => parseConfig("{ not json")).toThrow(/not valid JSON/);
  });

  test("rejects a non-array top level", () => {
    expect(() => parseConfig(`{"name":"x"}`)).toThrow(
      /top level must be an array/,
    );
  });

  test("rejects an empty or missing name, naming the entry index", () => {
    const bad = JSON.stringify([
      { name: "", lastRotated: "2026-01-01", rotationPolicyDays: 90, requiredBy: [] },
    ]);
    expect(() => parseConfig(bad)).toThrow(
      /secret at index 0: "name" must be a non-empty string/,
    );
  });

  test("rejects an invalid lastRotated date, naming the secret", () => {
    const bad = JSON.stringify([
      { name: "k", lastRotated: "not-a-date", rotationPolicyDays: 90, requiredBy: [] },
    ]);
    expect(() => parseConfig(bad)).toThrow(/secret "k": invalid date "not-a-date"/);
  });

  test("rejects calendar-impossible dates like 2026-02-30", () => {
    const bad = JSON.stringify([
      { name: "k", lastRotated: "2026-02-30", rotationPolicyDays: 90, requiredBy: [] },
    ]);
    expect(() => parseConfig(bad)).toThrow(/not a real calendar day/);
  });

  test("rejects a non-positive or non-integer rotation policy", () => {
    const bad = (days: unknown) =>
      JSON.stringify([
        { name: "k", lastRotated: "2026-01-01", rotationPolicyDays: days, requiredBy: [] },
      ]);
    expect(() => parseConfig(bad(-5))).toThrow(
      /"rotationPolicyDays" must be a positive integer/,
    );
    expect(() => parseConfig(bad(1.5))).toThrow(
      /"rotationPolicyDays" must be a positive integer/,
    );
  });

  test("rejects requiredBy that is not an array of strings", () => {
    const bad = JSON.stringify([
      { name: "k", lastRotated: "2026-01-01", rotationPolicyDays: 90, requiredBy: "oops" },
    ]);
    expect(() => parseConfig(bad)).toThrow(
      /"requiredBy" must be an array of service names/,
    );
  });

  test("rejects duplicate secret names", () => {
    const entry = {
      name: "dup",
      lastRotated: "2026-01-01",
      rotationPolicyDays: 90,
      requiredBy: [],
    };
    expect(() => parseConfig(JSON.stringify([entry, entry]))).toThrow(
      /duplicate secret name "dup"/,
    );
  });
});
