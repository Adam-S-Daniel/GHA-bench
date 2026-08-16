import { describe, it, expect, spyOn } from "bun:test";
import { spawn } from "bun";
import { readFileSync } from "fs";

describe("CLI Integration", () => {
  it("should read config from file and output JSON", async () => {
    const process = spawn(["bun", "run", "cli.ts", "fixtures/basic-config.json"], {
      cwd: import.meta.dir,
    });

    const output = await new Response(process.stdout).text();
    const result = JSON.parse(output);

    expect(result.include).toBeDefined();
    expect(Array.isArray(result.include)).toBe(true);
    expect(result.include.length).toBe(4); // 2 os × 2 node
  });

  it("should output properly formatted JSON", async () => {
    const process = spawn(["bun", "run", "cli.ts", "fixtures/basic-config.json"], {
      cwd: import.meta.dir,
    });

    const output = await new Response(process.stdout).text();
    const result = JSON.parse(output);

    expect(result).toHaveProperty("include");
    expect(result.include[0]).toHaveProperty("os");
    expect(result.include[0]).toHaveProperty("node");
  });

  it("should handle complex config with includes/excludes", async () => {
    const process = spawn(["bun", "run", "cli.ts", "fixtures/complex-config.json"], {
      cwd: import.meta.dir,
    });

    const output = await new Response(process.stdout).text();
    const result = JSON.parse(output);

    expect(result.include).toBeDefined();
    expect(result.exclude).toBeDefined();
    expect(result["max-parallel"]).toBe(6);
    expect(result["fail-fast"]).toBe(false);
  });

  it("should return error on oversized matrix", async () => {
    const process = spawn(["bun", "run", "cli.ts", "fixtures/oversized-config.json"], {
      cwd: import.meta.dir,
      stdio: ["inherit", "pipe", "pipe"],
    });

    const stderr = await new Response(process.stderr).text();
    const exitCode = await process.exited;

    expect(exitCode).not.toBe(0);
    expect(stderr).toContain("Matrix size");
  });

  it("should handle missing file gracefully", async () => {
    const process = spawn(["bun", "run", "cli.ts", "fixtures/nonexistent.json"], {
      cwd: import.meta.dir,
      stdio: ["inherit", "pipe", "pipe"],
    });

    const stderr = await new Response(process.stderr).text();
    const exitCode = await process.exited;

    expect(exitCode).not.toBe(0);
  });
});
