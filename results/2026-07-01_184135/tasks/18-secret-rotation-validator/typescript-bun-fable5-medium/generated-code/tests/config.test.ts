// RED/GREEN cycle 4: loading and validating the secrets configuration file.
//
// loadConfig must fail loudly and helpfully: missing file, malformed JSON,
// and schema violations each produce a distinct, actionable error message.
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadConfig } from "../src/config";

const dir = mkdtempSync(join(tmpdir(), "rotation-config-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

/** Write a fixture file into the temp dir and return its path. */
function fixture(name: string, content: string): string {
  const path = join(dir, name);
  writeFileSync(path, content);
  return path;
}

const VALID = {
  secrets: [
    {
      name: "db-password",
      lastRotated: "2026-03-01",
      rotationPolicyDays: 90,
      requiredBy: ["api", "worker"],
    },
  ],
};

describe("loadConfig", () => {
  test("loads a valid configuration", () => {
    const path = fixture("valid.json", JSON.stringify(VALID));
    const secrets = loadConfig(path);
    expect(secrets).toHaveLength(1);
    expect(secrets[0]!.name).toBe("db-password");
    expect(secrets[0]!.requiredBy).toEqual(["api", "worker"]);
  });

  test("missing file produces a meaningful error", () => {
    const path = join(dir, "nope.json");
    expect(() => loadConfig(path)).toThrow(
      `Configuration file not found: ${path}`,
    );
  });

  test("malformed JSON produces a meaningful error", () => {
    const path = fixture("bad.json", "{ not json ");
    expect(() => loadConfig(path)).toThrow(
      `Configuration file ${path} is not valid JSON`,
    );
  });

  test("missing secrets array produces a meaningful error", () => {
    const path = fixture("no-secrets.json", JSON.stringify({ foo: 1 }));
    expect(() => loadConfig(path)).toThrow(
      'Configuration must have a top-level "secrets" array',
    );
  });

  test("a secret with missing fields names the field and the entry", () => {
    const path = fixture(
      "missing-field.json",
      JSON.stringify({ secrets: [{ name: "x", lastRotated: "2026-01-01" }] }),
    );
    expect(() => loadConfig(path)).toThrow(
      'Secret "x" (entry #1): "rotationPolicyDays" must be a number',
    );
  });

  test("requiredBy must be an array of strings", () => {
    const path = fixture(
      "bad-required-by.json",
      JSON.stringify({
        secrets: [
          {
            name: "x",
            lastRotated: "2026-01-01",
            rotationPolicyDays: 30,
            requiredBy: "api",
          },
        ],
      }),
    );
    expect(() => loadConfig(path)).toThrow(
      'Secret "x" (entry #1): "requiredBy" must be an array of strings',
    );
  });
});
