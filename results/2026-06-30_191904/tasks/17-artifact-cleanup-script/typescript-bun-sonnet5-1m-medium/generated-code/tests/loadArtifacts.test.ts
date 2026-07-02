import { describe, test, expect } from "bun:test";
import { unlink } from "node:fs/promises";
import { loadArtifacts } from "../src/loadArtifacts";

describe("loadArtifacts", () => {
  test("parses a JSON file of artifacts", async () => {
    const artifacts = await loadArtifacts(
      `${import.meta.dir}/../fixtures/mock-artifacts.json`,
    );
    expect(artifacts.length).toBe(6);
    expect(artifacts[0]!.id).toBe("artifact-1001");
    expect(artifacts[0]!.sizeInBytes).toBe(52428800);
  });

  test("throws a meaningful error when the file does not exist", async () => {
    await expect(
      loadArtifacts(`${import.meta.dir}/../fixtures/does-not-exist.json`),
    ).rejects.toThrow(/does-not-exist\.json/);
  });

  test("throws a meaningful error when the JSON does not parse", async () => {
    const badFile = `${import.meta.dir}/../fixtures/bad.json`;
    await Bun.write(badFile, "{ not valid json");
    await expect(loadArtifacts(badFile)).rejects.toThrow(
      /Failed to parse artifacts file/,
    );
    await unlink(badFile);
  });
});
