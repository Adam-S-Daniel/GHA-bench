import { generateMatrix, MatrixConfig, MatrixOptions } from "./matrix";
import * as fs from "fs";

// Read configuration from JSON file or stdin
async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.error("Usage: cli.ts <config-file.json> [options-file.json]");
    process.exit(1);
  }

  try {
    // Read config file
    const configPath = args[0];
    if (!fs.existsSync(configPath)) {
      console.error(`Config file not found: ${configPath}`);
      process.exit(1);
    }

    const configContent = fs.readFileSync(configPath, "utf-8");
    const config: MatrixConfig = JSON.parse(configContent);

    // Read options file if provided
    let options: MatrixOptions | undefined;
    if (args[1]) {
      const optionsPath = args[1];
      if (fs.existsSync(optionsPath)) {
        const optionsContent = fs.readFileSync(optionsPath, "utf-8");
        options = JSON.parse(optionsContent);
      }
    }

    // Generate matrix
    const matrix = generateMatrix(config, options);

    // Output as JSON
    console.log(JSON.stringify(matrix, null, 2));
  } catch (error) {
    if (error instanceof Error) {
      console.error(`Error: ${error.message}`);
    } else {
      console.error(`Unknown error occurred`);
    }
    process.exit(1);
  }
}

main();
