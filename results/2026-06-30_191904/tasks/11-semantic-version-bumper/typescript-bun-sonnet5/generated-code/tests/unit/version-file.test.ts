// Unit tests for src/version-file.ts — reading/writing the version from
// either a package.json ("version" field) or a plain-text version file.
import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readVersionFile } from "../../src/version-file.ts";

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "svb-version-file-"));
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe("readVersionFile — package.json", () => {
  test("reads the version field from a package.json", async () => {
    const path = join(dir, "package.json");
    await Bun.write(
      path,
      JSON.stringify({ name: "demo", version: "1.2.3" }, null, 2),
    );

    const handle = await readVersionFile(path);
    expect(handle.version).toBe("1.2.3");
  });

  test("writing back updates only the version field, preserving the rest", async () => {
    const path = join(dir, "package.json");
    await Bun.write(
      path,
      JSON.stringify({ name: "demo", version: "1.2.3", private: true }, null, 2),
    );

    const handle = await readVersionFile(path);
    await handle.write("1.3.0");

    const updated = JSON.parse(await Bun.file(path).text());
    expect(updated).toEqual({ name: "demo", version: "1.3.0", private: true });
  });

  test("throws a descriptive error when 'version' is missing", async () => {
    const path = join(dir, "package.json");
    await Bun.write(path, JSON.stringify({ name: "demo" }));

    await expect(readVersionFile(path)).rejects.toThrow(
      /missing a "version" field/i,
    );
  });
});

describe("readVersionFile — plain text VERSION file", () => {
  test("reads the trimmed contents as the version", async () => {
    const path = join(dir, "VERSION");
    await Bun.write(path, "1.2.3\n");

    const handle = await readVersionFile(path);
    expect(handle.version).toBe("1.2.3");
  });

  test("writing back replaces the file contents with a trailing newline", async () => {
    const path = join(dir, "VERSION");
    await Bun.write(path, "1.2.3\n");

    const handle = await readVersionFile(path);
    await handle.write("2.0.0");

    expect(await Bun.file(path).text()).toBe("2.0.0\n");
  });
});

describe("readVersionFile — missing file", () => {
  test("throws a descriptive error", async () => {
    await expect(
      readVersionFile(join(dir, "does-not-exist.json")),
    ).rejects.toThrow(/version file not found/i);
  });
});
