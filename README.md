# GHA-bench

Benchmarks agent/scripting-language combinations on completing GitHub Actions scripting tasks when asked to use various languages. **[Latest results](results/2026-06-26_103905/results.md)** | [All results](#benchmark-runs)

## External References

[Introducing GHA-bench](https://adamdaniel.ai/blog/introducing-gha-bench/) on adamdaniel.ai.

> Interact with results and read more

## Benchmark Versions

### [v1](benchmark-instructions-v1.md) — Baseline

First benchmark run. 18 general scripting tasks (data transformation, text processing, file manipulation, etc.) across 4 language modes: `default`, `powershell`, `powershell-strict`, `csharp-script`. 2 models (Opus, Sonnet). 144 total runs. Every task prompt requires red/green TDD with mocks. No syntax hooks. Tasks 11-18 have GitHub Actions themes but only produce standalone scripts.

### [v2](benchmark-instructions-v2.md) — Refined Prompts

Same 18 tasks and 4 modes as v1, with improved prompt wording. Partially completed (111/144 runs) before being superseded by v3.

### [v3](benchmark-instructions-v3.md) — GitHub Actions Workflows

Narrowed to 8 tasks (11-18, all GHA-category). Changed modes to `default`, `powershell`, `bash`, `typescript-bun`. Each task now requires a working `.github/workflows/*.yml` file that passes `actionlint` and executes in Docker via `act`. All agent tests must run through the workflow pipeline. PostToolUse syntax/lint hooks enabled on all runs. 64 total runs.

### [v4](benchmark-instructions-v4.md) — Trap-Aware Guidance

Same 8 tasks as v3 (task 14 later archived, leaving 7). Added "Common Pitfalls" section derived from v3 trap analysis. `shell: pwsh` guidance for PowerShell mode. "Limit to 3 act push runs" instruction. Custom act container with pwsh/Pester pre-installed (`Dockerfile.act`). Cut average run time by 24% vs v3.

Modes expanded to 5: `default`, `powershell`, `bash`, `typescript-bun`, and `powershell-tool` (identical prompt to `powershell`, but with the [PowerShell tool](https://code.claude.com/docs/en/tools-reference#powershell-tool) enabled so the agent invokes `pwsh` natively instead of going through Bash). Models expanded beyond Opus/Sonnet 4.6 to include Opus 4.7 (high/medium/xhigh effort, 1M and 200K context), Sonnet 4.6 1M, and Haiku 4.5.

See also: [v3 design plan](design-and-planning-artifacts/PLAN-v3-gha.md) and other [design artifacts](design-and-planning-artifacts/).

## What it Tests

Each benchmark version defines a set of scripting tasks, language modes, and models. Agents receive only a prompt — no conversation context or prior results. Each run produces scripts, tests, and (in v3+) GitHub Actions workflows. Results are evaluated on:

- Whether the agent's own tests pass
- Code quality metrics (errors, turns, cost)
- Actionlint validation and act execution (v3+)
- PostToolUse hook effectiveness (v3+)
- Trap detection and analysis (v3+)

## Files

| File | Purpose |
|------|---------|
| `benchmark-instructions-v*.md` | Per-version methodology, task definitions, prompt templates |
| `models.py` | Model IDs and token pricing ([single source of truth](models.py)) |
| `runner.py` | Benchmark harness — invokes `claude -p`, collects metrics |
| `generate_results.py` | Generates `results.md` reports from metrics; updates this README |
| `combine_results.py` | Combines metrics from multiple run directories into a single comparison report (with pooled aggregates + per-CLI legend) |
| `monitor.py` | Live, read-only dashboard for an *in-flight* run: per-variant run-health + structural code/test metrics + live traps, an **automatic strongest-model-vs-strongest-model** head-to-head (current run's most powerful model+version vs the previous report's) broken down **per scripting language**, and (on subscription auth) the **weekly subscription allowance** (same data as `/usage`). Complements the post-run `generate_results.py` and the `watchdog.sh` process supervisor |
| `judge_consistency_report.py` | Produces the `Judge Consistency` panel summary from per-judge score caches |
| `conclusions_report.py` | Produces the combined Conclusions prose using a max-effort Claude CLI call |
| `results/analysis/` | Dated follow-up analyses (e.g. judge-disagreement spot-checks) referenced from the main reports |
| `test_quality.py` | Test quality evaluation — structural metrics + LLM-as-judge |
| `llm_providers.py` | Pluggable LLM provider abstraction for evaluation tasks |
| `hooks/syntax-check.py` | PostToolUse hook for syntax/lint checking (v3+) |
| `Dockerfile.act` | Custom act container with pwsh/Pester pre-installed (v4+) |
| `tests/` | Unit tests for repo code — run with `python3 -m pytest tests/ -v` |
| `.github/workflows/ci.yml` | CI workflow — runs tests and import validation on push/PR |
| `run-benchmark.sh` | One-command launcher with prerequisite checks |
| `results/` | Structured output — metrics.json, generated code, console logs per run |
| `workspaces/` | Temporary agent working directories (git-ignored) |
| `AGENTS.md` | Agent instructions ([agents.md spec](https://agents.md)) |
| `skills/` | Agent skills ([agentskills.io spec](https://agentskills.io/specification)) |
| `archived-tasks/` | Retired task definitions with rationale — results preserved in `results/` |
| `design-and-planning-artifacts/` | Historical planning docs, v1 analysis, superseded files |

## Benchmark Runs

<!-- BEGIN BENCHMARK RUNS -->
| Run | Version | Runs | Cost | Results |
|-----|---------|------|------|---------|
| **2026-06-26_103905** (latest) | [v4](benchmark-instructions-v4.md) | 140/35 | $577.71 | [results.md](results/2026-06-26_103905/results.md) |
| 2026-05-06_173435 | [v4](benchmark-instructions-v4.md) | 280/35 | $493.46 | [results.md](results/2026-05-06_173435/results.md) |
| 2026-04-17_004319 | [v4](benchmark-instructions-v4.md) | 245/50 | $360.74 | [results.md](results/2026-04-17_004319/results.md) |
| 2026-04-09_152435 | [v4](benchmark-instructions-v4.md) | 64/64 | $86.90 | [results.md](results/2026-04-09_152435/results.md) |
| 2026-04-08_192624 | [v3](benchmark-instructions-v3.md) | 64/64 | $85.10 | [results.md](results/2026-04-08_192624/results.md) |
| 2026-04-07_225702 | [v2](benchmark-instructions-v2.md) | 111/144 | $75.38 | [results.md](results/2026-04-07_225702/results.md) |
| 2026-04-02_163146 | [v1](benchmark-instructions-v1.md) | 144/144 | $436.67 | [results.md](results/2026-04-02_163146/results.md) |
<!-- END BENCHMARK RUNS -->

## Running a Benchmark

```bash
git clone https://github.com/Adam-S-Daniel/GHA-bench.git
cd GHA-bench

# Ensure claude CLI is installed and authenticated
# Then run:
./run-benchmark.sh
```

To resume a crashed/interrupted run:
```bash
./run-benchmark.sh --resume 2026-04-02_181500
```

To watch a run while it is still in progress (read-only live dashboard):
```bash
python3 monitor.py --total 140 --watch 30        # newest run; refresh every 30s
```
It prints per-variant run-health + structural code/test metrics + live traps, and an
automatic head-to-head between the **strongest model+version in this run** and the
**strongest in the previous report** (the newest completed run), broken down **per
scripting language** with the significant per-language differences called out.
Override the auto-selection with `--baseline DIR` and/or `--pair RUNVAR=BASEVAR`.
The ETA is pace-based (a floor — later, higher-effort tranches run slower). When the
session uses Claude-subscription auth (not an API key), it also reports the **weekly
subscription allowance** (the same five-hour + weekly limits as `/usage`); pass
`--no-usage` to skip that lookup.

To regenerate all results reports:
```bash
python3 generate_results.py --all
```

## Test Quality Evaluation

After a benchmark run, evaluate the quality of agent-generated test suites:

```bash
# Structural metrics only (fast, no LLM calls)
python3 test_quality.py results/2026-04-09_152435

# LLM-as-judge (requires a provider — default: claude-cli)
python3 test_quality.py --llm-judge --provider claude-cli results/2026-04-09_152435
```

Structural metrics count tests, assertions, and test-to-code ratios across Python, TypeScript, PowerShell, and Bash. The LLM-as-judge sends each run's code and tests to an LLM for scoring on four dimensions (1-5 scale):

- **Coverage**: Do tests exercise the key requirements?
- **Rigor**: Edge cases, error handling, boundary conditions?
- **Design**: Test organization, fixtures, readability?
- **Overall**: Holistic quality — primary ranking metric.

LLM judge results are cached per run (in `test-quality-llm.json`), so subsequent evaluations skip already-scored runs.

## Adding LLM Providers

The LLM-as-judge uses a pluggable provider system (`llm_providers.py`). The benchmark runner (`runner.py`) is inherently Claude CLI-based (it tests CLI features), but the evaluation layer is provider-agnostic.

**Current providers:**
- `claude-cli` — pre-authenticated Claude Code CLI. No API key or secrets needed.
- `agy` — pre-authenticated Antigravity CLI (`agy`). The Gemini path used by the panel's `gemini31pro` seat (default model `Gemini 3.1 Pro (High)`). No API key needed.
- `gemini-api` — `google-genai` SDK; requires `GEMINI_API_KEY` and a paid-tier Google AI Studio account.

> The `gemini-cli` provider was **removed on 2026-06-26**. Per Google: *"On June 18, 2026, Gemini CLI and Gemini Code Assist IDE extensions will stop serving requests for Google AI Pro and Ultra, as well as those using it free of charge using Gemini Code Assist for individuals."* ([source](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/)). Use `agy` (its Antigravity successor) instead; the old implementation is in git history.

**To add a new provider** (e.g., Anthropic API with key, OpenAI, Codex CLI):

1. Open `llm_providers.py`.
2. Create a class inheriting from `LLMProvider`.
3. Implement `is_available()` and `judge(system_prompt, user_message, model)`.
4. Register it in the `PROVIDERS` dict.
5. Use it: `python3 test_quality.py --llm-judge --provider your-provider`.

See the docstring in [`llm_providers.py`](llm_providers.py) for a complete skeleton example.
