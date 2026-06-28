// ---------------------------------------------------------------------------
// Shared type definitions for the environment matrix generator.
//
// These model both the user-supplied configuration and the generated GitHub
// Actions `strategy` object. Keeping them in one place lets the pure matrix
// logic (src/matrix.ts) and the CLI (src/generate.ts) agree on a single shape.
// ---------------------------------------------------------------------------

/**
 * A scalar that may appear as a matrix axis value. GitHub Actions matrices
 * commonly use strings, but numbers (e.g. node versions) and booleans (feature
 * flags) are valid too, so we preserve their original JSON type.
 */
export type MatrixValue = string | number | boolean;

/**
 * One fully-resolved matrix combination — a flat record of key -> value. Base
 * axis keys plus any extra keys contributed by `include` entries all live here.
 */
export type Combination = Record<string, MatrixValue>;

/**
 * The axes of the matrix: a map of axis name (e.g. "os", "node", "feature") to
 * the list of values that axis can take. This is the OS options / language
 * versions / feature flags described by the task, expressed generically so any
 * axis name is supported.
 */
export type MatrixAxes = Record<string, MatrixValue[]>;

/**
 * The user-supplied configuration document (typically parsed from JSON).
 */
export interface MatrixConfig {
  /** The base matrix axes (cartesian-producted together). */
  matrix: MatrixAxes;
  /** Extra combinations / partial overrides, GitHub `include` semantics. */
  include?: Combination[];
  /** Combinations to remove, GitHub `exclude` semantics (partial match). */
  exclude?: Combination[];
  /** Optional cap on concurrently-running matrix jobs. */
  maxParallel?: number;
  /** Whether to cancel all in-progress jobs if any matrix job fails. */
  failFast?: boolean;
  /**
   * Safety valve: if the generated matrix would contain more than this many
   * combinations, generation fails with an error instead of emitting a huge
   * matrix that GitHub itself would reject (GitHub's own hard limit is 256).
   */
  maxSize?: number;
}

/**
 * The generated strategy object, shaped so it can be dropped straight into a
 * GitHub Actions `strategy:` block. The fully-expanded combinations live under
 * `matrix.include`, which is GitHub's idiom for a dynamically-generated matrix.
 */
export interface GeneratedStrategy {
  matrix: { include: Combination[] };
  /** Number of combinations in `matrix.include` (convenience for consumers). */
  count: number;
  "max-parallel"?: number;
  "fail-fast"?: boolean;
}
