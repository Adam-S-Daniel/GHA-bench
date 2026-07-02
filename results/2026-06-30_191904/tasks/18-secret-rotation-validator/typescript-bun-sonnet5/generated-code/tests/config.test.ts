// Red/green TDD step 3: load + validate the secrets config file, with
// meaningful error messages for every way the mock data can be malformed.
import { describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadConfigFile, parseConfig } from "../src/config.ts";

describe("parseConfig", () => {
  test("accepts a well-formed config", () => {
    const config = parseConfig({
      warningWindowDays: 14,
      secrets: [
        {
          name: "db-password",
          lastRotated: "2026-06-01",
          rotationPolicyDays: 90,
          requiredBy: ["service-a"],
        },
      ],
    });
    expect(config.warningWindowDays).toBe(14);
    expect(config.secrets).toHaveLength(1);
  });

  test("defaults warningWindowDays to 14 when omitted", () => {
    const config = parseConfig({
      secrets: [
        {
          name: "db-password",
          lastRotated: "2026-06-01",
          rotationPolicyDays: 90,
          requiredBy: [],
        },
      ],
    });
    expect(config.warningWindowDays).toBe(14);
  });

  test("rejects a top-level value that isn't an object", () => {
    expect(() => parseConfig(null)).toThrow(/config must be a JSON object/i);
    expect(() => parseConfig("oops")).toThrow(/config must be a JSON object/i);
  });

  test("rejects a config missing the secrets array", () => {
    expect(() => parseConfig({})).toThrow(/"secrets" must be an array/i);
  });

  test("rejects a secret missing a name", () => {
    expect(() =>
      parseConfig({
        secrets: [{ lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: [] }],
      }),
    ).toThrow(/secrets\[0\].*name/i);
  });

  test("rejects a secret with a malformed lastRotated date", () => {
    expect(() =>
      parseConfig({
        secrets: [
          {
            name: "db-password",
            lastRotated: "not-a-date",
            rotationPolicyDays: 90,
            requiredBy: [],
          },
        ],
      }),
    ).toThrow(/secrets\[0\].*lastRotated/i);
  });

  test("rejects a secret with a non-positive rotationPolicyDays", () => {
    expect(() =>
      parseConfig({
        secrets: [
          {
            name: "db-password",
            lastRotated: "2026-06-01",
            rotationPolicyDays: -5,
            requiredBy: [],
          },
        ],
      }),
    ).toThrow(/secrets\[0\].*rotationPolicyDays/i);
  });

  test("rejects a secret whose requiredBy is not an array of strings", () => {
    expect(() =>
      parseConfig({
        secrets: [
          {
            name: "db-password",
            lastRotated: "2026-06-01",
            rotationPolicyDays: 90,
            requiredBy: "service-a",
          },
        ],
      }),
    ).toThrow(/secrets\[0\].*requiredBy/i);
  });

  test("rejects a negative warningWindowDays", () => {
    expect(() =>
      parseConfig({
        warningWindowDays: -1,
        secrets: [],
      }),
    ).toThrow(/warningWindowDays/i);
  });
});

describe("loadConfigFile", () => {
  test("loads and parses a valid config from disk", async () => {
    const dir = await mkdtemp(join(tmpdir(), "secret-rotation-"));
    try {
      const path = join(dir, "config.json");
      await writeFile(
        path,
        JSON.stringify({
          secrets: [
            {
              name: "db-password",
              lastRotated: "2026-06-01",
              rotationPolicyDays: 90,
              requiredBy: ["service-a"],
            },
          ],
        }),
      );
      const config = await loadConfigFile(path);
      expect(config.secrets[0]?.name).toBe("db-password");
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  test("throws a meaningful error when the file does not exist", async () => {
    await expect(loadConfigFile("/nonexistent/path/config.json")).rejects.toThrow(
      /could not read config file/i,
    );
  });

  test("throws a meaningful error when the file is not valid JSON", async () => {
    const dir = await mkdtemp(join(tmpdir(), "secret-rotation-"));
    try {
      const path = join(dir, "config.json");
      await writeFile(path, "{ not valid json");
      await expect(loadConfigFile(path)).rejects.toThrow(/invalid json/i);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
