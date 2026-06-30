# ---------------------------------------------------------------------------
# Model definitions and token pricing — SINGLE SOURCE OF TRUTH
# ---------------------------------------------------------------------------
# Every file in this repo that needs model IDs or token costs imports from
# here.  There is no other place these values are defined.
#
# TO UPDATE: check https://docs.anthropic.com/en/docs/about-claude/models
# and https://www.anthropic.com/pricing for current prices.  Update the
# values below, then run:
#     python3 generate_results.py --all
# to regenerate all reports with the new rates.
# ---------------------------------------------------------------------------

MODELS = {
    "opus": "claude-opus-4-6",
    "sonnet": "claude-sonnet-4-6",
    "opus48": "claude-opus-4-8",
    "opus48-1m": "claude-opus-4-8[1m]",
    "opus47-200k": "claude-opus-4-7",
    "opus47-1m": "claude-opus-4-7[1m]",
    "opus46-1m": "claude-opus-4-6[1m]",
    "sonnet46-1m": "claude-sonnet-4-6[1m]",
    "sonnet5": "claude-sonnet-5",
    "sonnet5-1m": "claude-sonnet-5[1m]",
    "haiku45": "claude-haiku-4-5",
}

# All costs in USD per million tokens. Source: https://claude.com/pricing
# cache_write is the 5-minute TTL rate (1.25x base input). 1-hour TTL cache
# writes are documented as 2x base input but Anthropic appears to bill Claude
# Code CLI cache creation at the 5m rate regardless of TTL tag (confirmed
# empirically against a probe run on claude-opus-4-7[1m] — reported cost
# matched 5m-rate math to the penny).
# `[1m]` variants extend the context window to 1M tokens; the pricing docs
# state pricing "applies uniformly regardless of context length", so these
# entries mirror the base-model rates.
# These are assumption fields — the CLI's reported `total_cost_usd` is the
# authoritative per-run cost and is what appears in results.md.
COST_PER_MTOK = {
    "claude-opus-4-6":       {"input": 5.0, "output": 25.0, "cache_read": 0.50, "cache_write": 6.25},
    "claude-opus-4-7":       {"input": 5.0, "output": 25.0, "cache_read": 0.50, "cache_write": 6.25},
    "claude-opus-4-8":       {"input": 5.0, "output": 25.0, "cache_read": 0.50, "cache_write": 6.25},
    "claude-opus-4-8[1m]":   {"input": 5.0, "output": 25.0, "cache_read": 0.50, "cache_write": 6.25},
    "claude-opus-4-6[1m]":   {"input": 5.0, "output": 25.0, "cache_read": 0.50, "cache_write": 6.25},
    "claude-opus-4-7[1m]":   {"input": 5.0, "output": 25.0, "cache_read": 0.50, "cache_write": 6.25},
    "claude-sonnet-4-6":     {"input": 3.0, "output": 15.0, "cache_read": 0.30, "cache_write": 3.75},
    "claude-sonnet-4-6[1m]": {"input": 3.0, "output": 15.0, "cache_read": 0.30, "cache_write": 3.75},
    # Sonnet 5 launched at the standard sonnet tier ($3 in / $15 out). An
    # introductory promotion of $2 in / $10 out runs through 2026-08-31; we
    # record the standard tier here, and the CLI's reported `total_cost_usd`
    # (which already reflects any active promo) remains authoritative in results.
    "claude-sonnet-5":       {"input": 3.0, "output": 15.0, "cache_read": 0.30, "cache_write": 3.75},
    "claude-sonnet-5[1m]":   {"input": 3.0, "output": 15.0, "cache_read": 0.30, "cache_write": 3.75},
    "claude-haiku-4-5":      {"input": 1.0, "output": 5.0,  "cache_read": 0.10, "cache_write": 1.25},
}
