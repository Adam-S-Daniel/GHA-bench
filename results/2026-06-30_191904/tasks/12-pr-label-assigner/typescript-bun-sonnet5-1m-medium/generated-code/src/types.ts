/** A single path-to-label mapping rule. */
export interface LabelRule {
  /** Glob pattern matched against each changed file path (see glob.ts). */
  pattern: string;
  /** Label applied when at least one changed file matches `pattern`. */
  label: string;
  /**
   * Priority used to resolve conflicts within an `exclusiveGroup`.
   * Higher numbers win. Defaults to 0 when omitted.
   */
  priority?: number;
  /**
   * Rules sharing the same `exclusiveGroup` are mutually exclusive:
   * only the highest-priority triggered rule in the group contributes
   * its label. Rules without an `exclusiveGroup` never conflict and
   * always contribute their label when triggered.
   */
  exclusiveGroup?: string;
}
