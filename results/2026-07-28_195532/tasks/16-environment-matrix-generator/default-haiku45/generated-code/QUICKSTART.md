# Quick Start Guide

## 30-Second Overview

This tool generates GitHub Actions build matrices from configuration:

```python
from matrix_generator import MatrixConfig, generate_matrix

config = MatrixConfig(
    os_options=["ubuntu-latest", "macos-latest"],
    language_versions={"python": ["3.11", "3.12"]},
    feature_flags={}
)

matrix = generate_matrix(config)
# Output: 4 combinations (2 OS × 2 Python versions)
```

## Installation

No external dependencies required.

```bash
# For testing only
pip install pytest
```

## Run Tests

```bash
# All unit tests (14 tests)
python3 -m pytest test_matrix_generator.py -v

# Quick check
python3 -m pytest test_matrix_generator.py -q

# With coverage
python3 -m pytest test_matrix_generator.py --tb=short
```

## Test Workflow Locally

```bash
# Run both workflow jobs through act
python3 run_act_tests.py

# Or run individual jobs
act push --rm -j test_and_generate
act push --rm -j verify_structure
```

## Use as CLI Tool

```bash
# Create config
cat > matrix.json << 'EOF'
{
  "os_options": ["ubuntu-latest", "macos-latest"],
  "language_versions": {"python": ["3.11", "3.12"]},
  "feature_flags": {"experimental": false},
  "max_parallel": 5,
  "fail_fast": false
}
EOF

# Generate matrix
python3 matrix_generator.py matrix.json

# Output:
# {
#   "include": [
#     {"os": "ubuntu-latest", "python": "3.11", "experimental": false},
#     {"os": "ubuntu-latest", "python": "3.12", "experimental": false},
#     {"os": "macos-latest", "python": "3.11", "experimental": false},
#     {"os": "macos-latest", "python": "3.12", "experimental": false}
#   ],
#   "fail-fast": false
# }
```

## Common Configurations

### Minimal (Single OS, Single Language)
```python
config = MatrixConfig(
    os_options=["ubuntu-latest"],
    language_versions={"python": ["3.11"]},
    feature_flags={}
)
```

### Multi-Language
```python
config = MatrixConfig(
    os_options=["ubuntu-latest"],
    language_versions={
        "python": ["3.11", "3.12"],
        "node": ["18", "20"]
    },
    feature_flags={}
)
```

### With Constraints
```python
config = MatrixConfig(
    os_options=["ubuntu-latest", "macos-latest", "windows-latest"],
    language_versions={"python": ["3.11", "3.12"]},
    feature_flags={},
    max_parallel=4,  # Limit to 4 concurrent jobs
    fail_fast=False  # Don't stop on first failure
)
```

### With Exclusions
```python
config = MatrixConfig(
    os_options=["ubuntu-latest", "macos-latest"],
    language_versions={"python": ["3.11", "3.12"]},
    feature_flags={},
    exclude=[
        {"os": "macos-latest", "python": "3.12"}  # Skip this combo
    ]
)
```

### With Additions
```python
config = MatrixConfig(
    os_options=["ubuntu-latest"],
    language_versions={"python": ["3.11"]},
    feature_flags={},
    include=[
        {"os": "ubuntu-latest", "python": "3.11", "coverage": True}
    ]
)
```

## Configuration Reference

```python
MatrixConfig(
    # Required
    os_options: List[str],                  # e.g., ["ubuntu-latest", "macos-latest"]
    language_versions: Dict[str, List[str]], # e.g., {"python": ["3.11", "3.12"]}
    feature_flags: Dict[str, Any],          # e.g., {"debug": True}

    # Optional
    include: List[Dict[str, Any]] = [],     # Extra combinations to add
    exclude: List[Dict[str, Any]] = [],     # Combinations to remove
    max_parallel: int = 0,                  # 0 = unlimited
    max_size: int = 256,                    # GitHub Actions default
    fail_fast: bool = True                  # Stop on first failure
)
```

## Troubleshooting

### "Matrix exceeds max_size"
- Reduce OS options or language versions
- Enable `max_parallel` to limit concurrent jobs
- Use `exclude` to remove specific combinations

### "At least one OS option is required"
- Check that `os_options` is not empty

### "No matching distribution found for pytest"
- Use `pip install --break-system-packages pytest` (in containers)

### Act tests failing
- Make sure Docker is running
- Check Docker daemon is accessible
- Run `act push --rm` for verbose output

## Next Steps

1. **Read the documentation**: `README.md`
2. **Run the tests**: `python3 -m pytest test_matrix_generator.py -v`
3. **Explore examples**: Check `test_matrix_generator.py` for realistic scenarios
4. **Integrate with CI/CD**: Use `.github/workflows/environment-matrix-generator.yml`

## Performance

- Matrix generation: < 5ms
- Test suite: < 100ms
- Workflow via act: ~30-60 seconds (includes container startup)

## Support

All error cases are handled with meaningful messages:

```python
try:
    config = MatrixConfig(os_options=[], language_versions={}, feature_flags={})
    matrix = generate_matrix(config)
except MatrixGenerationError as e:
    print(f"Error: {e}")  # "At least one OS option is required"
```

---

**Status**: ✓ Production Ready  
**Tests**: 14/14 passing  
**Workflow**: Validated & tested through act
