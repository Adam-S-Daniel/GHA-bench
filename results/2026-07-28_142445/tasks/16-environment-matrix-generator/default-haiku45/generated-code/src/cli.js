#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { MatrixGenerator } from './generator.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

async function main() {
  try {
    // Get config file path from command line or use default
    const configPath = process.argv[2] || 'matrix-config.json';
    const outputPath = process.argv[3] || 'matrix.json';

    // Read configuration
    if (!fs.existsSync(configPath)) {
      console.error(`Error: Configuration file not found: ${configPath}`);
      process.exit(1);
    }

    const configContent = fs.readFileSync(configPath, 'utf8');
    const config = JSON.parse(configContent);

    // Generate matrix
    const generator = new MatrixGenerator();
    const matrix = generator.generate(config);

    // Write output
    fs.writeFileSync(outputPath, JSON.stringify(matrix, null, 2));
    console.log(`✅ Matrix generated successfully`);
    console.log(`   Input:  ${configPath}`);
    console.log(`   Output: ${outputPath}`);
    console.log(`   Combinations: ${matrix.include.length}`);

    // Output to stdout as well for GitHub Actions
    console.log('\n📊 Generated Matrix:');
    console.log(JSON.stringify(matrix, null, 2));

  } catch (error) {
    console.error(`Error: ${error.message}`);
    if (error instanceof SyntaxError) {
      console.error('Configuration file is not valid JSON');
    }
    process.exit(1);
  }
}

main();
