# Cell collection complete

**Run:** `2026-06-26_103905` — opus-4.8 (1M) campaign (`opus48-1m` = `claude-opus-4-8[1m]`)

**Status:** All **140/140** cells collected (7 tasks × 5 languages × 4 efforts: medium, high, xhigh, ultracode). Reached 2026-06-28 ~17:39 ET.

- **136 successful**, 4 failed — the 4 failures are the known pre-existing **xhigh PowerShell-family 30-min timeouts** (12/powershell-tool, 13/powershell, 16/powershell-tool, 17/powershell-tool), not rate-limit related.
- **Rate-limit clean:** 0 `overloaded_error` / `rate_limit_error` / "temporarily limiting" / HTTP 529 markers across all 140 cells.
- CC versions: 2.1.193 (23 medium cells) + 2.1.195 (117 cells); current `claude` = 2.1.195.

**This file is the early signal that cell collection is finished** — it is safe to do unrelated heavy Claude work on this machine/account. Judging (panel of judges: Haiku 4.5 + Gemini 3.1 Pro via `agy`), prior-run concurrency/incident audits, the trap investigation, the consolidated cross-run report, and draft blog posts follow in subsequent PRs.
