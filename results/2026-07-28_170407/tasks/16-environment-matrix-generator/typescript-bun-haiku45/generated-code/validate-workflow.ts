// Validate workflow structure and content
import * as fs from "fs";
import * as path from "path";
import * as yaml from "https://deno.land/std@0.208.0/yaml/mod.ts";

const workflowPath = ".github/workflows/environment-matrix-generator.yml";

async function validateWorkflow() {
  console.log("Validating workflow structure...\n");

  // Check file exists
  if (!fs.existsSync(workflowPath)) {
    console.error(`❌ Workflow file not found: ${workflowPath}`);
    process.exit(1);
  }
  console.log(`✅ Workflow file exists at ${workflowPath}`);

  // Read and parse YAML
  const content = fs.readFileSync(workflowPath, "utf-8");
  let workflow: any;

  try {
    workflow = yaml.parse(content) as any;
  } catch (err) {
    console.error("❌ Failed to parse workflow YAML");
    if (err instanceof Error) {
      console.error(err.message);
    }
    process.exit(1);
  }
  console.log("✅ Workflow YAML is valid");

  // Validate required fields
  const errors: string[] = [];

  if (!workflow.name) {
    errors.push("Missing 'name' field");
  } else {
    console.log(`✅ Workflow name: ${workflow.name}`);
  }

  if (!workflow.on) {
    errors.push("Missing 'on' field");
  } else {
    console.log(`✅ Workflow has triggers: ${Object.keys(workflow.on).join(", ")}`);
  }

  if (!workflow.jobs) {
    errors.push("Missing 'jobs' field");
  } else {
    console.log(`✅ Workflow has ${Object.keys(workflow.jobs).length} job(s)`);
  }

  // Validate job structure
  if (workflow.jobs) {
    for (const [jobName, job] of Object.entries(workflow.jobs)) {
      const jobObj = job as any;

      if (!jobObj.runs_on && !jobObj["runs-on"]) {
        errors.push(`Job '${jobName}': missing 'runs-on' field`);
      } else {
        console.log(`✅ Job '${jobName}' has runs-on defined`);
      }

      if (!jobObj.steps || !Array.isArray(jobObj.steps)) {
        errors.push(`Job '${jobName}': missing or invalid 'steps' field`);
      } else {
        console.log(
          `✅ Job '${jobName}' has ${jobObj.steps.length} step(s)`
        );

        // Verify key steps
        const stepNames = jobObj.steps
          .map((s: any) => s.name || s.uses || s.run || "unnamed")
          .join(", ");
        console.log(`   Steps: ${stepNames}`);
      }
    }
  }

  // Check for specific required files
  const requiredFiles = ["matrix.ts", "cli.ts", "matrix.test.ts", "cli.test.ts"];
  console.log("\nVerifying required files exist:");
  for (const file of requiredFiles) {
    if (fs.existsSync(file)) {
      console.log(`✅ ${file}`);
    } else {
      errors.push(`Missing required file: ${file}`);
    }
  }

  if (errors.length > 0) {
    console.error("\n❌ Validation errors:");
    errors.forEach((err) => console.error(`  - ${err}`));
    process.exit(1);
  }

  console.log("\n✅ All workflow structure validations passed!");
}

validateWorkflow().catch((err) => {
  console.error("Error validating workflow:", err);
  process.exit(1);
});
