// TDD for the CLI rendering layer.
//
// The workflow runs `cli.ts` inside an `act` container and parses its stdout.
// To keep that parsing robust we emit unambiguous marker lines. These tests
// pin down the exact marker format so the act harness can assert on it.
import { test, expect } from "bun:test";
import { renderResult, renderError } from "./cli";
import { generateMatrix } from "./matrix-generator";

test("renderResult emits MTX_COUNT, MTX_STRATEGY and MTX_JSON markers", () => {
  const result = generateMatrix({ os: ["ubuntu-latest", "windows-latest"], language: ["20"] });
  const output = renderResult(result);

  expect(output).toContain("MTX_COUNT=2");

  // The STRATEGY marker must contain valid JSON for the strategy block.
  const strategyLine = output.split("\n").find((l) => l.startsWith("MTX_STRATEGY="))!;
  const strategy = JSON.parse(strategyLine.replace("MTX_STRATEGY=", ""));
  expect(strategy["fail-fast"]).toBe(true);
  expect(strategy.matrix.os).toEqual(["ubuntu-latest", "windows-latest"]);

  // The MATRIX marker carries the fully-expanded combinations as JSON.
  const matrixLine = output.split("\n").find((l) => l.startsWith("MTX_JSON="))!;
  const combos = JSON.parse(matrixLine.replace("MTX_JSON=", ""));
  expect(combos).toHaveLength(2);
});

test("renderError emits an MTX_ERROR marker with the message", () => {
  const output = renderError(new Error("boom"));
  expect(output).toContain("MTX_ERROR=boom");
});
