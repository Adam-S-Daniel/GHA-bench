// License lookup abstraction. In production, looking up a package's license
// would call an external registry (npm, PyPI); that's slow, flaky, and
// unavailable in offline CI containers. Instead we depend on a small
// interface that can be backed by an in-memory map (unit tests) or a JSON
// fixture file (deterministic "mock" used by the CLI and its CI pipeline).

import type { Dependency } from "./types";

export interface LicenseLookup {
  lookup(dep: Dependency): Promise<string | null>;
}

/** In-memory license lookup, keyed by "name@version" with an optional "name" fallback. */
export class InMemoryLicenseLookup implements LicenseLookup {
  private readonly entries: Record<string, string>;

  constructor(entries: Record<string, string>) {
    this.entries = entries;
  }

  async lookup(dep: Dependency): Promise<string | null> {
    const exact = this.entries[`${dep.name}@${dep.version}`];
    if (exact) return exact;

    const byName = this.entries[dep.name];
    return byName ?? null;
  }
}

/** Loads a license map from a JSON fixture file and delegates to InMemoryLicenseLookup. */
export class FixtureLicenseLookup implements LicenseLookup {
  private readonly inner: InMemoryLicenseLookup;

  private constructor(entries: Record<string, string>) {
    this.inner = new InMemoryLicenseLookup(entries);
  }

  static async fromFile(path: string): Promise<FixtureLicenseLookup> {
    const file = Bun.file(path);
    if (!(await file.exists())) {
      throw new Error(`License fixture not found: ${path}`);
    }

    let entries: Record<string, string>;
    try {
      entries = await file.json();
    } catch (err) {
      throw new Error(`License fixture at ${path} is not valid JSON (${(err as Error).message})`);
    }

    return new FixtureLicenseLookup(entries);
  }

  async lookup(dep: Dependency): Promise<string | null> {
    return this.inner.lookup(dep);
  }
}
