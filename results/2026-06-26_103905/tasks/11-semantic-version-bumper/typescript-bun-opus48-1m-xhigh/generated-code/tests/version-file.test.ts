// RED phase for the version-file reader/writer.
//
// The bumper must support two on-disk shapes:
//   1. a package.json (read/write the "version" field, preserve the rest)
//   2. a plain text file containing just the version (optionally "v"-prefixed)
// Detection is by file extension; writing round-trips the original shape.
import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readVersionFile, writeVersionFile } from "../src/version-file.ts";

let dir: string;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "svb-vf-"));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("readVersionFile", () => {
  it("reads the version field from a package.json", async () => {
    const p = join(dir, "package.json");
    writeFileSync(p, JSON.stringify({ name: "demo", version: "1.2.3" }, null, 2));
    const vf = await readVersionFile(p);
    expect(vf.format).toBe("json");
    expect(vf.version).toBe("1.2.3");
  });

  it("reads a plain version file and strips a 'v' prefix", async () => {
    const p = join(dir, "VERSION");
    writeFileSync(p, "v2.0.0\n");
    const vf = await readVersionFile(p);
    expect(vf.format).toBe("plain");
    expect(vf.version).toBe("2.0.0");
    expect(vf.hasVPrefix).toBe(true);
  });

  it("throws a clear error when the file is missing", async () => {
    await expect(readVersionFile(join(dir, "nope.txt"))).rejects.toThrow(
      /version file not found/i,
    );
  });

  it("throws when a package.json has no version field", async () => {
    const p = join(dir, "package.json");
    writeFileSync(p, JSON.stringify({ name: "demo" }));
    await expect(readVersionFile(p)).rejects.toThrow(/no "version" field/i);
  });

  it("throws when a package.json is not valid JSON", async () => {
    const p = join(dir, "package.json");
    writeFileSync(p, "{ not json ");
    await expect(readVersionFile(p)).rejects.toThrow(/could not parse/i);
  });
});

describe("writeVersionFile", () => {
  it("updates only the version field of a package.json and preserves keys", async () => {
    const p = join(dir, "package.json");
    writeFileSync(
      p,
      JSON.stringify({ name: "demo", version: "1.2.3", scripts: { a: "b" } }, null, 2),
    );
    const vf = await readVersionFile(p);
    await writeVersionFile(vf, "1.3.0");

    const parsed = JSON.parse(readFileSync(p, "utf8"));
    expect(parsed.version).toBe("1.3.0");
    expect(parsed.name).toBe("demo");
    expect(parsed.scripts).toEqual({ a: "b" });
    // Ends with a trailing newline (well-behaved text files do).
    expect(readFileSync(p, "utf8").endsWith("\n")).toBe(true);
  });

  it("writes a plain file, restoring the 'v' prefix when the original had one", async () => {
    const p = join(dir, "VERSION");
    writeFileSync(p, "v2.0.0\n");
    const vf = await readVersionFile(p);
    await writeVersionFile(vf, "3.0.0");
    expect(readFileSync(p, "utf8")).toBe("v3.0.0\n");
  });

  it("writes a plain file without a prefix when the original had none", async () => {
    const p = join(dir, "VERSION");
    writeFileSync(p, "2.0.0");
    const vf = await readVersionFile(p);
    await writeVersionFile(vf, "2.0.1");
    expect(readFileSync(p, "utf8")).toBe("2.0.1\n");
  });
});
