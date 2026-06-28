"""Unit tests for llm_providers.py — provider registry and availability."""

import pytest

import inspect

from llm_providers import (
    ClaudeCLIProvider,
    AgyCLIProvider,
    LLMProvider,
    PROVIDERS,
    DEFAULT_PROVIDER,
    get_provider,
)


class TestProviderRegistry:
    def test_claude_cli_registered(self):
        assert "claude-cli" in PROVIDERS

    def test_default_provider_is_claude_cli(self):
        assert DEFAULT_PROVIDER == "claude-cli"

    def test_get_provider_returns_instance(self):
        # This may raise RuntimeError if CLI not available, which is fine
        try:
            p = get_provider("claude-cli")
            assert isinstance(p, ClaudeCLIProvider)
            assert isinstance(p, LLMProvider)
        except RuntimeError:
            pytest.skip("claude CLI not available in this environment")

    def test_agy_registered(self):
        # Antigravity CLI provider (gemini-cli replacement after Google retired
        # Gemini Code Assist for individuals).
        assert "agy" in PROVIDERS

    def test_get_provider_unknown_raises(self):
        with pytest.raises(ValueError, match="Unknown provider"):
            get_provider("nonexistent-provider")

    def test_get_provider_default(self):
        try:
            p = get_provider(None)
            assert p.name == "claude-cli"
        except RuntimeError:
            pytest.skip("claude CLI not available")


class TestClaudeCLIProvider:
    def test_name(self):
        p = ClaudeCLIProvider()
        assert p.name == "claude-cli"

    def test_is_available_returns_bool(self):
        p = ClaudeCLIProvider()
        result = p.is_available()
        assert isinstance(result, bool)

    def test_provider_has_judge_method(self):
        p = ClaudeCLIProvider()
        assert callable(p.judge)


class TestAgyCLIProvider:
    def test_name(self):
        assert AgyCLIProvider().name == "agy"

    def test_is_available_returns_bool(self):
        assert isinstance(AgyCLIProvider().is_available(), bool)

    def test_provider_has_judge_method(self):
        assert callable(AgyCLIProvider().judge)

    def test_default_model_matches_previous_report(self):
        # Gemini 3.1 Pro at the (High) tier — matches the prior report's
        # gemini-3.1-pro-preview model + default high thinking.
        default = inspect.signature(AgyCLIProvider().judge).parameters["model"].default
        assert default == "Gemini 3.1 Pro (High)"


class TestGeminiJudgeWiring:
    def test_gemini31pro_judge_uses_agy(self):
        # The cross-family panel's Gemini seat must run through agy now.
        from test_quality import JUDGES
        cfg = JUDGES["gemini31pro"]
        assert cfg["provider"] == "agy"
        assert cfg["model"] == "Gemini 3.1 Pro (High)"


class TestLLMProviderInterface:
    def test_cannot_instantiate_base(self):
        with pytest.raises(TypeError):
            LLMProvider()

    def test_subclass_must_implement_methods(self):
        class IncompleteProvider(LLMProvider):
            name = "incomplete"

        with pytest.raises(TypeError):
            IncompleteProvider()

    def test_partial_subclass_missing_judge(self):
        class NoJudge(LLMProvider):
            name = "no-judge"
            def is_available(self): return True

        with pytest.raises(TypeError):
            NoJudge()

    def test_partial_subclass_missing_is_available(self):
        class NoAvailability(LLMProvider):
            name = "no-avail"
            def judge(self, *a, **kw): pass

        with pytest.raises(TypeError):
            NoAvailability()
