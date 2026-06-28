# Root-level conftest so pytest inserts the project root onto sys.path.
# This lets `tests/test_semver_bumper.py` do `import semver_bumper`
# even though the test lives in the tests/ subdirectory.
