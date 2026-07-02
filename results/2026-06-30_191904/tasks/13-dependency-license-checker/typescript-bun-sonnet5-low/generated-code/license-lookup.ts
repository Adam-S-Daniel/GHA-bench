import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { Dependency, LicenseLookup } from "./types";

/**
 * Builds a LicenseLookup that reads the `license` field from an installed
 * dependency's own package.json under node_modules. Works fully offline,
 * which keeps the checker deterministic in CI.
 */
export function createNodeModulesLicenseLookup(rootDir: string): LicenseLookup {
  return async (dep: Dependency) => {
    const pkgPath = join(rootDir, "node_modules", dep.name, "package.json");
    if (!existsSync(pkgPath)) return null;

    const raw = readFileSync(pkgPath, "utf-8");
    const pkg = JSON.parse(raw) as { license?: string | { type?: string } };

    if (!pkg.license) return null;
    if (typeof pkg.license === "string") return pkg.license;
    return pkg.license.type ?? null;
  };
}
