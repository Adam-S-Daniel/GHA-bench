#!/usr/bin/env python3
"""Variability analysis for the 2026-07-28 cloud campaign.

Three contrasts, all on the same 8 cells (haiku45 x tasks 11,16 x 4 languages):

  within-arm   3 replicates of one config           -> how noisy is one cell?
  A vs B       CC 2.1.220 vs 2.1.132, cloud both    -> the CLI version effect
  B vs laptop  cloud vs laptop, CC ~fixed           -> the environment effect

Everything is done on log(duration) and log(cost): these are ratio-scale
quantities, the noise is multiplicative, and a paired log difference averaged
over cells is exactly "the typical x-factor". Cells are the unit of pairing,
so each contrast is a paired comparison over 8 cells, not 24 loose numbers.
"""
import glob, json, math, os, sys
from statistics import mean, stdev

LAPTOP = "2026-05-06_173435"
# The laptop corpus also carries powershell-tool cells; the cloud campaign ran
# only these four, so every contrast is restricted to them.
MODES = ("bash", "default", "powershell", "typescript-bun")
ARMS = {"A": [], "B": []}  # filled from .campaign markers, plus the un-marked first run
ARM_A_FIRST = "2026-07-28_114218"

# t critical values, two-sided 95%, by degrees of freedom
T95 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365,
       8: 2.306, 9: 2.262, 10: 2.228, 15: 2.131, 16: 2.120, 20: 2.086}


def load(run):
    """{(task, lang): (duration_s, cost_usd)} for the 8 haiku45 cells."""
    out = {}
    for f in glob.glob(f"results/{run}/tasks/*/*-haiku45/metrics.json"):
        p = f.split("/")
        task, lang = p[3][:2], p[4].replace("-haiku45", "")
        if task in ("11", "16") and lang in MODES:
            d = json.load(open(f))
            out[(task, lang)] = (d["timing"]["grand_total_duration_ms"] / 1000,
                                 d["cost"]["total_cost_usd"])
    return out


def discover():
    for d in sorted(glob.glob("results/2026-07-28_*/")):
        marker = os.path.join(d, ".campaign")
        if os.path.exists(marker):
            arm = open(marker).read().split()[1]
            ARMS[arm].append(os.path.basename(d.rstrip("/")))
    ARMS["A"].insert(0, ARM_A_FIRST)


def gm(xs):
    return math.exp(mean([math.log(x) for x in xs]))


def paired_ratio(num, den, keys, idx):
    """Geometric-mean ratio num/den over cells, with a paired t 95% CI.

    num/den map cell -> list of replicate values (or a single value).
    """
    diffs = []
    for k in keys:
        a = mean([math.log(v[idx]) for v in num[k]])
        b = mean([math.log(v[idx]) for v in den[k]])
        diffs.append(a - b)
    n = len(diffs)
    m = mean(diffs)
    se = stdev(diffs) / math.sqrt(n)
    t = T95.get(n - 1, 2.0)
    return math.exp(m), math.exp(m - t * se), math.exp(m + t * se)


def within_arm_sigma(reps, keys, idx):
    """Pooled within-cell SD of log value, as a multiplicative 1 sigma."""
    per_cell, dfs = [], 0
    for k in keys:
        vals = [math.log(r[k][idx]) for r in reps if k in r]
        if len(vals) > 1:
            per_cell.append(stdev(vals) ** 2 * (len(vals) - 1))
            dfs += len(vals) - 1
    return math.exp(math.sqrt(sum(per_cell) / dfs)) if dfs else float("nan")


def main():
    discover()
    laptop = load(LAPTOP)
    arm = {a: [load(r) for r in runs] for a, runs in ARMS.items()}
    keys = sorted(laptop)

    for a in ("A", "B"):
        complete = [r for r in arm[a] if len(r) == 8]
        print(f"arm {a}: {len(complete)}/{len(arm[a])} complete replicates {ARMS[a]}")
        arm[a] = complete
    if not all(arm.values()):
        sys.exit("not enough complete replicates yet")

    for label, idx, unit in (("DURATION", 0, "s"), ("COST", 1, "$")):
        print(f"\n{'='*74}\n{label}\n{'='*74}")
        print(f"{'cell':22s}" + "".join(f"{'A r'+str(i+1):>9s}" for i in range(len(arm['A'])))
              + "".join(f"{'B r'+str(i+1):>9s}" for i in range(len(arm['B']))) + f"{'laptop':>10s}")
        for k in keys:
            row = f"{k[0]+'/'+k[1]:22s}"
            for a in ("A", "B"):
                row += "".join(f"{r[k][idx]:9.0f}" if idx == 0 else f"{r[k][idx]:9.2f}" for r in arm[a])
            row += f"{laptop[k][idx]:10.0f}" if idx == 0 else f"{laptop[k][idx]:10.2f}"
            print(row)

        print(f"\nper-replicate totals ({unit}):")
        for a in ("A", "B"):
            tot = [sum(r[k][idx] for k in keys) for r in arm[a]]
            div = 60 if idx == 0 else 1
            print(f"  arm {a}: " + ", ".join(f"{t/div:.1f}" for t in tot)
                  + f"   (spread {max(tot)/min(tot):.2f}x)")
        tl = sum(laptop[k][idx] for k in keys) / (60 if idx == 0 else 1)
        print(f"  laptop: {tl:.1f}")

        print("\nwithin-arm noise on a single cell (pooled 1 sigma, multiplicative):")
        for a in ("A", "B"):
            s = within_arm_sigma(arm[a], keys, idx)
            print(f"  arm {a}: {s:.2f}x   (95% of single cells within {1/s**2:.2f}-{s**2:.2f}x of that cell's mean)")

        print("\npaired contrasts (geometric mean over 8 cells, 95% CI):")
        r, lo, hi = paired_ratio({k: [r[k] for r in arm["A"]] for k in keys},
                                 {k: [r[k] for r in arm["B"]] for k in keys}, keys, idx)
        print(f"  A/B    CC 2.1.220 vs 2.1.132, environment fixed : {r:.3f}x  [{lo:.3f}, {hi:.3f}]"
              + ("  <- CI excludes 1.0" if lo > 1 or hi < 1 else "  <- CI includes 1.0"))
        r, lo, hi = paired_ratio({k: [r[k] for r in arm["B"]] for k in keys},
                                 {k: [laptop[k]] for k in keys}, keys, idx)
        print(f"  B/lap  cloud vs laptop, CC ~fixed              : {r:.3f}x  [{lo:.3f}, {hi:.3f}]"
              + ("  <- CI excludes 1.0" if lo > 1 or hi < 1 else "  <- CI includes 1.0"))
        r, lo, hi = paired_ratio({k: [r[k] for r in arm["A"]] for k in keys},
                                 {k: [laptop[k]] for k in keys}, keys, idx)
        print(f"  A/lap  both differ (version + environment)     : {r:.3f}x  [{lo:.3f}, {hi:.3f}]"
              + ("  <- CI excludes 1.0" if lo > 1 or hi < 1 else "  <- CI includes 1.0"))

    # How much replication would a given effect need? Uses the pooled single-cell
    # sigma and the paired 8-cell design actually used here.
    print(f"\n{'='*74}\nDETECTION POWER (duration, 8 paired cells)\n{'='*74}")
    s = math.log(within_arm_sigma(arm["A"] + arm["B"], keys, 0))
    for eff in (1.05, 1.10, 1.20, 1.50):
        # SE of a paired log ratio with n replicates per arm, 8 cells
        need = None
        for n in range(1, 200):
            se = math.sqrt(2 * s**2 / n / 8)
            if math.log(eff) > 1.96 * se:
                need = n
                break
        print(f"  detect a {eff:.2f}x effect: needs ~{need} replicate(s) per arm"
              f"  (SE at n=3: {math.exp(math.sqrt(2*s**2/3/8)):.3f}x)")

    ok = sum(1 for a in ("A", "B") for r in arm[a] for k in keys)
    print(f"\ncells analysed: {ok} cloud + 8 laptop")


if __name__ == "__main__":
    main()
