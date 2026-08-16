#!/usr/bin/env bun

import { generateMatrix, MatrixConfig } from "./matrix";
import { readFileSync } from "fs";

const args = process.argv.slice(2);

if (args.length === 0) {
  console.error("Usage: bun cli.ts <config-file.json>");
  console.error("   or: bun cli.ts --stdin");
  process.exit(1);
}

async function main() {
  try {
    let configText: string;

    if (args[0] === "--stdin") {
      // Read config from stdin
      const chunks: Buffer[] = [];
      for await (const chunk of Bun.stdin.stream()) {
        chunks.push(chunk);
      }
      configText = Buffer.concat(chunks).toString();
    } else {
      // Read config from file
      const filePath = args[0];
      configText = readFileSync(filePath, "utf-8");
    }

    const config: MatrixConfig = JSON.parse(configText);

    // Generate the matrix
    const matrix = generateMatrix(config);

    // Output as JSON to stdout
    console.log(JSON.stringify(matrix, null, 2));
    process.exit(0);
  } catch (error: any) {
    console.error("Error:", error.message);
    process.exit(1);
  }
}

main();
