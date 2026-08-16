# Quick Start Guide

## Installation

The script is ready to use immediately. No installation required.

```bash
# Make sure it's executable
chmod +x matrix-generator.sh

# Verify it works
./matrix-generator.sh --help
```

## Basic Usage

### 1. Create a configuration file

```bash
cat > my-matrix.json << 'EOF'
{
  "os": ["ubuntu-latest", "macos-latest"],
  "python": ["3.9", "3.10", "3.11"]
}
EOF
```

### 2. Generate the matrix

```bash
./matrix-generator.sh my-matrix.json
```

Output:
```json
{"matrix":{"os":["macos-latest","ubuntu-latest"],"python":["3.10","3.11","3.9"]}}
```

### 3. Use in GitHub Actions

Create a workflow file (`.github/workflows/test.yml`):

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: ["ubuntu-latest", "macos-latest"]
        python: ["3.9", "3.10", "3.11"]
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: ${{ matrix.python }}
```

Or generate it dynamically:

```yaml
name: Test

on: [push, pull_request]

jobs:
  generate-matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.gen.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - id: gen
        run: echo "matrix=$(./matrix-generator.sh matrix.json)" >> $GITHUB_OUTPUT

  test:
    needs: generate-matrix
    runs-on: ${{ matrix.os }}
    strategy:
      matrix: ${{ fromJson(needs.generate-matrix.outputs.matrix) }}
    steps:
      - uses: actions/checkout@v4
```

## Configuration Reference

### Minimal Config

```json
{
  "os": ["ubuntu-latest"]
}
```

### Full Config

```json
{
  "os": ["ubuntu-latest", "macos-latest", "windows-latest"],
  "language": ["python", "node", "ruby"],
  "version": ["1.0", "2.0", "3.0"],
  "max_matrix_size": 256,
  "include": [
    {"os": "macos-latest", "language": "swift"}
  ],
  "exclude": [
    {"os": "windows-latest", "language": "ruby"}
  ],
  "strategy": {
    "fail-fast": true,
    "max-parallel": 4
  }
}
```

### Key Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Any dimension | array | — | Creates a dimension in the matrix |
| `max_matrix_size` | number | 256 | Maximum allowed combinations |
| `include` | array | [] | Additional combinations to add |
| `exclude` | array | [] | Combinations to remove |
| `strategy.fail-fast` | boolean | — | Stop all jobs if one fails |
| `strategy.max-parallel` | number | — | Max concurrent jobs |

## Command Line Options

```bash
./matrix-generator.sh [options] <config-file>

Options:
  -h, --help              Show help message
  --max-size SIZE         Override max matrix size (default: 256)
```

## Examples

### Simple Matrix

```json
{
  "os": ["ubuntu-latest", "macos-latest"]
}
```

### Multi-Dimensional Matrix

```json
{
  "os": ["ubuntu-latest", "macos-latest"],
  "python": ["3.9", "3.10", "3.11"],
  "node": ["16", "18", "20"]
}
```

### With Include/Exclude

```json
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node": ["16", "18"],
  "include": [
    {"os": "windows-latest", "node": "18"}
  ],
  "exclude": [
    {"os": "macos-latest", "node": "16"}
  ]
}
```

### Override Size Limit

```bash
# Via configuration
{
  "max_matrix_size": 50,
  "os": ["ubuntu", "macos", "windows"],
  "version": ["1", "2", "3", "4", "5"]
}

# Via command line
./matrix-generator.sh --max-size 50 config.json
```

## Testing

Run the test suite:

```bash
# Run all tests
bats tests/test_matrix_generator.bats

# Run with verbose output
bats -v tests/test_matrix_generator.bats
```

Run validation:

```bash
# Check script syntax
bash -n matrix-generator.sh

# Check shell best practices
shellcheck matrix-generator.sh
```

## Troubleshooting

### "Configuration file not found"
- Check that the file path is correct
- Verify the file exists: `ls -l config.json`

### "Invalid JSON in configuration file"
- Validate your JSON: `jq . config.json`
- Check for missing commas, quotes, or brackets

### "Matrix size would exceed maximum"
- Reduce the number of values in dimensions
- Increase `max_matrix_size` in the config
- Use `--max-size` command line option
- Use `exclude` to remove unwanted combinations

### "bash: ./matrix-generator.sh: Permission denied"
- Make it executable: `chmod +x matrix-generator.sh`

## Output Format

The script outputs a JSON object with:

```json
{
  "matrix": {
    "dimension1": ["value1", "value2", ...],
    "dimension2": ["value3", "value4", ...],
    "strategy_key": value
  },
  "include": [...],
  "exclude": [...]
}
```

This is ready to use with GitHub Actions strategy.matrix or any other matrix-based CI system.

## Performance

- Small matrices (< 100 items): < 100ms
- Medium matrices (100-1000 items): < 500ms
- Large matrices (> 1000 items): depends on size

## Support

For issues or questions, check:
- IMPLEMENTATION.md for complete documentation
- Test suite in tests/test_matrix_generator.bats for usage examples
- GitHub Actions workflow in .github/workflows/ for integration examples
