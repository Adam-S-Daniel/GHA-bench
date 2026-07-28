import { promises as fs } from "fs";

// Validate workflow structure without YAML parsing
async function validateWorkflow(): Promise<boolean> {
  console.log("Validating workflow structure...\n");

  try {
    // Read workflow file
    const workflowPath = ".github/workflows/semantic-version-bumper.yml";
    const yamlContent = await fs.readFile(workflowPath, "utf-8");

    // Check file exists and has content
    console.log("✓ Workflow file exists");

    if (!yamlContent.includes("name: Semantic Version Bumper")) {
      console.error("✗ Workflow name not found");
      return false;
    }
    console.log("✓ Workflow name found");

    // Check for trigger events
    if (!yamlContent.includes("on:")) {
      console.error("✗ Workflow missing 'on' trigger");
      return false;
    }
    console.log("✓ Workflow has triggers defined");

    // Check for jobs
    if (!yamlContent.includes("jobs:")) {
      console.error("✗ Workflow missing 'jobs' section");
      return false;
    }
    console.log("✓ Workflow has jobs defined");

    // Validate expected jobs
    const expectedJobs = [
      "test-unit",
      "test-fixtures",
      "validate-workflow",
      "type-check",
      "integration",
    ];

    for (const job of expectedJobs) {
      if (!yamlContent.includes(`${job}:`)) {
        console.warn(`⚠ Expected job '${job}' not found`);
      } else {
        console.log(`✓ Job '${job}' found`);
      }
    }

    // Verify script files exist
    const requiredFiles = [
      "version-bumper.ts",
      "cli.ts",
      "test-fixtures.sh",
      "version-bumper.test.ts",
    ];

    for (const file of requiredFiles) {
      try {
        await fs.access(file);
        console.log(`✓ Script file exists: ${file}`);
      } catch {
        console.error(`✗ Script file missing: ${file}`);
        return false;
      }
    }

    // Verify fixture files exist
    const fixtureFiles = [
      "fixtures/commits-patch.txt",
      "fixtures/commits-minor.txt",
      "fixtures/commits-major.txt",
    ];

    for (const file of fixtureFiles) {
      try {
        await fs.access(file);
        console.log(`✓ Fixture file exists: ${file}`);
      } catch {
        console.error(`✗ Fixture file missing: ${file}`);
        return false;
      }
    }

    console.log("\n✓ All workflow structure validations passed!");
    return true;
  } catch (error) {
    console.error("✗ Workflow validation failed:", error);
    return false;
  }
}

validateWorkflow().then((success) => {
  process.exit(success ? 0 : 1);
});
