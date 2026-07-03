"""LLM provider abstraction for benchmark evaluation tasks.

This module provides a pluggable interface for calling LLMs. The benchmark
runner (runner.py) is inherently tied to the Claude Code CLI since it tests
CLI-specific features (streaming, workspace isolation, per-mode tooling). This provider
layer is for *evaluation* tasks like the LLM-as-judge in test_quality.py,
where the LLM is used as a tool rather than being the thing under test.

CURRENT PROVIDERS
=================
- claude-cli: Uses the pre-authenticated Claude Code CLI (`claude -p`).
              No API key or additional config required — works with any
              authenticated Claude Code installation (subscription, API key,
              or OAuth).

ADDING A NEW PROVIDER
=====================
1. Create a new class that inherits from LLMProvider.
2. Implement the `judge()` method: takes a system prompt and user message,
   returns a dict with {"text": str, "cost_usd": float, "input_tokens": int,
   "output_tokens": int} or None on failure.
3. Implement the `is_available()` method: returns True if the provider can
   be used (e.g., CLI is on PATH, or API key is set).
4. Register the provider in the PROVIDERS dict at the bottom of this file.
5. Add any new dependencies to the docstring and AGENTS.md.

Example skeleton for an Anthropic API provider:

    class AnthropicAPIProvider(LLMProvider):
        name = "anthropic-api"

        def is_available(self) -> bool:
            try:
                import anthropic  # noqa: F401
                return bool(os.environ.get("ANTHROPIC_API_KEY"))
            except ImportError:
                return False

        def judge(self, system_prompt: str, user_message: str,
                  model: str = "claude-sonnet-4-6") -> dict | None:
            import anthropic
            client = anthropic.Anthropic()
            response = client.messages.create(
                model=model, max_tokens=1024, system=system_prompt,
                messages=[{"role": "user", "content": user_message}],
            )
            return {
                "text": response.content[0].text,
                "cost_usd": ...,  # compute from response.usage
                "input_tokens": response.usage.input_tokens,
                "output_tokens": response.usage.output_tokens,
            }
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from abc import ABC, abstractmethod


class LLMProvider(ABC):
    """Base class for LLM providers used in evaluation tasks."""

    name: str = "base"

    @abstractmethod
    def is_available(self) -> bool:
        """Return True if this provider is ready to use."""
        ...

    @abstractmethod
    def judge(self, system_prompt: str, user_message: str,
              model: str = "sonnet") -> dict | None:
        """Send a prompt and return the response.

        Args:
            system_prompt: System-level instructions for the LLM.
            user_message: The user message (task description + code).
            model: Model alias or ID. Providers map this to their own
                   model identifiers as needed.

        Returns:
            dict with keys:
                text: str — the model's text response
                cost_usd: float — cost of this call (0 if unknown/free)
                input_tokens: int — input tokens used
                output_tokens: int — output tokens used
            or None if the call failed.
        """
        ...


class ClaudeCLIProvider(LLMProvider):
    """LLM provider using the pre-authenticated Claude Code CLI.

    Uses `claude -p` with `--output-format json`. Works with any
    authentication method the CLI supports (subscription, API key, OAuth).
    No additional configuration required.
    """

    name = "claude-cli"

    def is_available(self) -> bool:
        return shutil.which("claude") is not None

    def judge(self, system_prompt: str, user_message: str,
              model: str = "sonnet",
              effort: str | None = None,
              max_budget_usd: float = 0.50,
              timeout_s: int = 120) -> dict | None:
        # Run from a temp dir to avoid CLAUDE.md auto-discovery
        judge_dir = tempfile.mkdtemp(prefix="llm-judge-")
        cmd = [
            "claude", "-p",
            "--model", model,
            "--system-prompt", system_prompt,
            "--output-format", "json",
            "--max-budget-usd", f"{max_budget_usd:.2f}",
        ]
        if effort:
            cmd.extend(["--effort", effort])
        try:
            result = subprocess.run(
                cmd,
                input=user_message,
                capture_output=True,
                text=True,
                timeout=timeout_s,
                cwd=judge_dir,
            )
        except subprocess.TimeoutExpired:
            print(f"  [{self.name}] timed out ({timeout_s}s)", file=sys.stderr)
            return None
        except Exception as e:
            print(f"  [{self.name}] subprocess error: {e}", file=sys.stderr)
            return None
        finally:
            shutil.rmtree(judge_dir, ignore_errors=True)

        if result.returncode != 0:
            snippet = result.stderr[:200] if result.stderr else "(no stderr)"
            print(f"  [{self.name}] CLI failed (exit {result.returncode}): {snippet}",
                  file=sys.stderr)
            return None

        try:
            parsed = json.loads(result.stdout)
        except json.JSONDecodeError:
            print(f"  [{self.name}] non-JSON output: {result.stdout[:200]}",
                  file=sys.stderr)
            return None

        # CLI may return an array of events (stream) or a single object.
        # Extract the result event.
        if isinstance(parsed, list):
            envelope = next((e for e in parsed if e.get("type") == "result"), parsed[-1] if parsed else {})
        else:
            envelope = parsed

        if envelope.get("is_error"):
            print(f"  [{self.name}] error: {envelope.get('result', '')[:200]}",
                  file=sys.stderr)
            return None

        # Strip markdown fences if present
        raw = envelope.get("result", "")
        text = re.sub(r"^```(?:json)?\s*\n?", "", raw.strip())
        text = re.sub(r"\n?```\s*$", "", text).strip()

        usage = envelope.get("usage", {})
        return {
            "text": text,
            "cost_usd": envelope.get("total_cost_usd", 0),
            "input_tokens": usage.get("input_tokens", 0),
            "output_tokens": usage.get("output_tokens", 0),
        }


# ---------------------------------------------------------------------------
# Gemini Developer API provider
# ---------------------------------------------------------------------------
# Cross-family judge. Uses the google-genai SDK (Developer API flavour)
# reading GEMINI_API_KEY from the environment. Pricing (April 2026) for
# Gemini 3.1 Pro is $2/$12 per 1M tokens at ≤200K context; outputs are
# typically 200-2000 tokens for our rubric so per-call cost lands ~$0.03-
# 0.05. Billing is computed from the SDK's usage fields if present,
# otherwise derived from our own per-1M rates below.

# Model → (input $/M, output $/M) for the ≤200K context tier.
_GEMINI_PRICE_PER_MTOK = {
    "gemini-3.1-pro":               (2.00, 12.00),
    "gemini-3.1-pro-preview":       (2.00, 12.00),
    "gemini-3.1-pro-latest":        (2.00, 12.00),
    "gemini-3.1-flash":             (0.30, 2.50),
    "gemini-3.1-flash-lite":        (0.25, 1.50),
    "gemini-3.1-flash-lite-preview": (0.25, 1.50),
    "gemini-3-pro-preview":         (2.00, 12.00),
    "gemini-2.5-pro":               (1.00, 10.00),
    "gemini-2.5-flash":              (0.30, 2.50),
    "gemini-2.5-flash-lite":         (0.10, 0.40),
}


class GeminiAPIProvider(LLMProvider):
    """LLM provider using Google's Gemini Developer API.

    Requires `GEMINI_API_KEY` in the environment and the `google-genai`
    SDK installed. Default model is `gemini-3.1-pro` (current flagship as
    of April 2026) — the judge dimensions in test_quality.py match
    Gemini's JSON output format well.
    """

    name = "gemini-api"

    def is_available(self) -> bool:
        try:
            from google import genai  # noqa: F401
        except ImportError:
            return False
        return bool(os.environ.get("GEMINI_API_KEY"))

    def judge(self, system_prompt: str, user_message: str,
              model: str = "gemini-3.1-pro") -> dict | None:
        try:
            from google import genai
            from google.genai import types as genai_types
        except ImportError:
            print(f"  [{self.name}] google-genai SDK not installed", file=sys.stderr)
            return None

        try:
            client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
            resp = client.models.generate_content(
                model=model,
                contents=user_message,
                config=genai_types.GenerateContentConfig(
                    system_instruction=system_prompt,
                    # JSON-forced responses are more reliable than markdown-
                    # fenced JSON; the rubric already specifies the schema.
                    response_mime_type="application/json",
                    # Low temperature keeps scores more consistent across
                    # repeat runs of the same input.
                    temperature=0.2,
                ),
            )
        except Exception as e:
            print(f"  [{self.name}] API error: {type(e).__name__}: {e}",
                  file=sys.stderr)
            return None

        text = getattr(resp, "text", None)
        if not text:
            print(f"  [{self.name}] empty response", file=sys.stderr)
            return None
        # Strip any residual markdown fences defensively.
        text = re.sub(r"^```(?:json)?\s*\n?", "", text.strip())
        text = re.sub(r"\n?```\s*$", "", text).strip()

        # Prefer SDK-reported usage; otherwise compute from price table.
        usage = getattr(resp, "usage_metadata", None)
        in_tok = getattr(usage, "prompt_token_count", 0) if usage else 0
        out_tok = getattr(usage, "candidates_token_count", 0) if usage else 0
        rates = _GEMINI_PRICE_PER_MTOK.get(model, (2.0, 12.0))
        cost = (in_tok / 1_000_000) * rates[0] + (out_tok / 1_000_000) * rates[1]

        return {
            "text": text,
            "cost_usd": round(cost, 6),
            "input_tokens": int(in_tok),
            "output_tokens": int(out_tok),
        }


# ---------------------------------------------------------------------------
# Gemini CLI provider — REMOVED 2026-06-26
# ---------------------------------------------------------------------------
# The `gemini-cli` provider (class GeminiCLIProvider, name "gemini-cli") was
# deleted after Google retired the Gemini CLI for subscription and individual
# use:
#
#   "On June 18, 2026, Gemini CLI and Gemini Code Assist IDE extensions will
#    stop serving requests for Google AI Pro and Ultra, as well as those using
#    it free of charge using Gemini Code Assist for individuals."
#   — https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/
#
# Its replacement is the Antigravity CLI provider (`agy`, AgyCLIProvider below),
# which the `gemini31pro` judge now uses. `gemini-api` remains for hosts with a
# paid Google AI Studio key. The pre-removal implementation is in git history.


# The Antigravity CLI (`agy`) — Google's successor for individuals after Gemini
# Code Assist for individuals was retired (the `gemini` CLI now returns
# IneligibleTierError: UNSUPPORTED_CLIENT). Like the former gemini-cli provider
# it runs one prompt non-interactively, but `agy -p` prints the response text
# directly (there is no `-o json` envelope), so stdout *is* the response. We run
# from a fresh temp dir so no local workspace/config is loaded, and
# --dangerously-skip-permissions so the headless call never blocks on a prompt
# (the judge prompt is self-contained, so no tools are actually invoked). `agy
# --print` does not report token stats, so cost/tokens are 0 here — the run's
# authoritative cost is the Claude CLI's, and judge cost is informational only.

class AgyCLIProvider(LLMProvider):
    """LLM provider using the pre-authenticated Antigravity CLI (`agy`).

    Drop-in replacement for the removed gemini-cli provider. The default model
    "Gemini 3.1 Pro (High)" matches the model and (high) thinking depth the
    previous report's `gemini-3.1-pro-preview` judge used — agy exposes Gemini
    3.1 Pro as explicit (Low)/(High) effort tiers; (High) corresponds to the
    preview's default full-thinking behaviour.
    """

    name = "agy"

    def is_available(self) -> bool:
        return shutil.which("agy") is not None

    def judge(self, system_prompt: str, user_message: str,
              model: str = "Gemini 3.1 Pro (High)",
              timeout_s: int | None = None) -> dict | None:
        if timeout_s is None:
            timeout_s = int(os.environ.get("AGY_TIMEOUT_S", "300"))
        combined = f"{system_prompt}\n\n---\n\n{user_message}"
        judge_dir = tempfile.mkdtemp(prefix="agy-judge-")
        try:
            result = subprocess.run(
                ["agy", "-p", combined, "--model", model,
                 "--dangerously-skip-permissions"],
                capture_output=True, text=True, timeout=timeout_s, cwd=judge_dir,
            )
        except subprocess.TimeoutExpired:
            print(f"  [{self.name}] timed out ({timeout_s}s)", file=sys.stderr)
            return None
        except Exception as e:
            print(f"  [{self.name}] subprocess error: {e}", file=sys.stderr)
            return None
        finally:
            shutil.rmtree(judge_dir, ignore_errors=True)

        if result.returncode != 0:
            snippet = result.stderr[:200] if result.stderr else "(no stderr)"
            print(f"  [{self.name}] CLI failed (exit {result.returncode}): {snippet}",
                  file=sys.stderr)
            return None

        raw = result.stdout.strip()
        # Strip any markdown fences the model added despite the instruction.
        text = re.sub(r"^```(?:json)?\s*\n?", "", raw)
        text = re.sub(r"\n?```\s*$", "", text).strip()
        if not text:
            print(f"  [{self.name}] empty response", file=sys.stderr)
            return None
        return {
            "text": text,
            "cost_usd": 0.0,      # agy --print does not report token stats
            "input_tokens": 0,
            "output_tokens": 0,
        }


# ---------------------------------------------------------------------------
# Provider registry
# ---------------------------------------------------------------------------

PROVIDERS: dict[str, type[LLMProvider]] = {
    "claude-cli": ClaudeCLIProvider,
    "gemini-api": GeminiAPIProvider,
    "agy": AgyCLIProvider,
}

DEFAULT_PROVIDER = "claude-cli"


def get_provider(name: str | None = None) -> LLMProvider:
    """Get an LLM provider instance by name.

    Args:
        name: Provider name (key in PROVIDERS). If None, uses DEFAULT_PROVIDER.

    Returns:
        An instantiated LLMProvider.

    Raises:
        ValueError: If the provider name is unknown.
        RuntimeError: If the provider is not available.
    """
    name = name or DEFAULT_PROVIDER
    cls = PROVIDERS.get(name)
    if cls is None:
        available = ", ".join(PROVIDERS.keys())
        raise ValueError(f"Unknown provider '{name}'. Available: {available}")
    provider = cls()
    if not provider.is_available():
        raise RuntimeError(
            f"Provider '{name}' is not available. "
            f"Check that the required tools/credentials are configured."
        )
    return provider
