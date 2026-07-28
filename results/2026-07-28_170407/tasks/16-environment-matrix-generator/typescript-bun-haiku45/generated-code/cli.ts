import { generateMatrix, serializeMatrixJSON, MatrixConfig } from "./matrix";
import * as fs from "fs";
import * as path from "path";

async function main() {
  try {
    let configInput: string;
    let configFile: string | undefined;

    // Check for command-line argument (config file path)
    if (process.argv.length > 2) {
      configFile = process.argv[2];
    }

    // Read config from file or stdin
    if (configFile) {
      if (!fs.existsSync(configFile)) {
        console.error(`Error: Config file not found: ${configFile}`);
        process.exit(1);
      }
      configInput = fs.readFileSync(configFile, "utf-8");
    } else {
      // Read from stdin
      configInput = await readStdin();
    }

    // Parse JSON config
    let config: MatrixConfig;
    try {
      config = JSON.parse(configInput);
    } catch (err) {
      console.error("Error: Invalid JSON in config");
      if (err instanceof Error) {
        console.error(err.message);
      }
      process.exit(1);
    }

    // Generate matrix
    const result = generateMatrix(config);

    // Output as JSON
    const json = serializeMatrixJSON(result);
    console.log(json);

    process.exit(0);
  } catch (err) {
    console.error("Error generating matrix:");
    if (err instanceof Error) {
      console.error(err.message);
    }
    process.exit(1);
  }
}

async function readStdin(): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = "";

    process.stdin.setEncoding("utf-8");
    process.stdin.on("readable", () => {
      let chunk;
      while ((chunk = process.stdin.read()) !== null) {
        data += chunk;
      }
    });

    process.stdin.on("end", () => {
      resolve(data);
    });

    process.stdin.on("error", (err) => {
      reject(err);
    });
  });
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
