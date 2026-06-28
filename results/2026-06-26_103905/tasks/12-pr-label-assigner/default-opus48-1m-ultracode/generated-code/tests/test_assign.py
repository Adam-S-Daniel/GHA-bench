"""Red/green TDD — Step 2: rule evaluation.

``assign_labels(files, rules)`` is the heart of the assigner. A *rule* is a
mapping::

    {"pattern": "docs/**", "labels": ["documentation"], "priority": 10,
     "group": "area"}   # priority + group are optional

Contract exercised below:

* every rule whose glob matches a changed file contributes its label(s)
  (supporting **multiple labels per file** and the same label from many files);
* the result's ``labels`` is the **set** of all applied labels, ordered by
  effective priority (highest first), ties broken alphabetically — this is the
  "priority ordering" requirement;
* when two matching rules share a ``group`` for the *same file*, only the
  higher-priority rule applies — this is the "priority ordering when rules
  conflict" requirement;
* a per-file breakdown is returned for transparency.
"""

import pr_label_assigner as pla


def test_single_rule_single_file():
    rules = [{"pattern": "docs/**", "labels": ["documentation"]}]
    result = pla.assign_labels(["docs/guide.md"], rules)
    assert result["labels"] == ["documentation"]
    assert result["by_file"]["docs/guide.md"] == ["documentation"]


def test_multiple_labels_per_file():
    rules = [{"pattern": "src/api/**", "labels": ["api", "backend"]}]
    result = pla.assign_labels(["src/api/v1/users.py"], rules)
    assert result["labels"] == ["api", "backend"]


def test_union_across_files_is_deduplicated():
    rules = [{"pattern": "*.test.*", "labels": ["tests"]}]
    result = pla.assign_labels(["a.test.js", "b.test.js"], rules)
    assert result["labels"] == ["tests"]  # one label, not two


def test_priority_orders_the_output():
    rules = [
        {"pattern": "docs/**", "labels": ["documentation"], "priority": 1},
        {"pattern": "src/api/**", "labels": ["api"], "priority": 100},
        {"pattern": "*.test.*", "labels": ["tests"], "priority": 50},
    ]
    files = ["docs/x.md", "src/api/y.py", "z.test.js"]
    result = pla.assign_labels(files, rules)
    # Highest priority first; equal priorities would fall back to name order.
    assert result["labels"] == ["api", "tests", "documentation"]


def test_group_conflict_resolved_by_priority():
    # Both rules match docs/internal/secret.md, but they share group "area";
    # the higher-priority rule wins for that file.
    rules = [
        {"pattern": "docs/**", "labels": ["documentation"],
         "priority": 1, "group": "area"},
        {"pattern": "docs/internal/**", "labels": ["internal-docs"],
         "priority": 10, "group": "area"},
    ]
    result = pla.assign_labels(["docs/internal/secret.md"], rules)
    assert result["labels"] == ["internal-docs"]
    assert result["by_file"]["docs/internal/secret.md"] == ["internal-docs"]


def test_rules_without_group_never_conflict():
    rules = [
        {"pattern": "docs/**", "labels": ["documentation"], "priority": 1},
        {"pattern": "docs/internal/**", "labels": ["internal-docs"], "priority": 10},
    ]
    result = pla.assign_labels(["docs/internal/secret.md"], rules)
    assert result["labels"] == ["internal-docs", "documentation"]


def test_no_matching_rule_yields_no_labels():
    rules = [{"pattern": "docs/**", "labels": ["documentation"]}]
    result = pla.assign_labels(["src/main.py"], rules)
    assert result["labels"] == []
    assert result["by_file"]["src/main.py"] == []


def test_empty_file_list():
    rules = [{"pattern": "docs/**", "labels": ["documentation"]}]
    result = pla.assign_labels([], rules)
    assert result["labels"] == []
    assert result["by_file"] == {}
