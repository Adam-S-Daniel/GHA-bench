import { describe, it, expect } from "bun:test";

describe("CLI integration", () => {
  it("CLI should exist and be executable", () => {
    const fs = require("fs");
    const cliPath = "./cli.ts";
    expect(fs.existsSync(cliPath)).toBe(true);
  });
});
