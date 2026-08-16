# GitHub Actions Build Matrix Generator

A Bash script that generates GitHub Actions build matrices from JSON configuration files. Supports dynamic matrix generation with include/exclude rules, strategy configuration, and size validation.

## Features

- **Cartesian Product Generation**: Automatically generates all combinations of OS, language versions, and feature flags
- **Include Rules**: Add custom matrix entries beyond the cartesian product
- **Exclude Rules**: Remove specific combinations from the generated matrix
- **Strategy Configuration**: Set `fail-fast` and `max-parallel` behavior for GitHub Actions
- **Matrix Size Validation**: Enforces maximum matrix size to prevent resource exhaustion
- **Error Handling**: Comprehensive validation with meaningful error messages
- **JSON Output**: Generates complete GitHub Actions strategy.matrix JSON

## Installation

```bash
# Clone or copy the script
cp src/matrix-generator.sh /usr/local/bin/matrix-generator
chmod +x /usr/local/bin/matrix-generator
```

### Dependencies

- `bash` (4.0+)
- `jq` (for JSON processing)

Install on Ubuntu/Debian:
```bash
apt-get update && apt-get install -y jq
```

## Usage

```bash
matrix-generator.sh <config-file>
```

### Configuration File Format

Create a JSON file describing your matrix:

```json
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node-version": ["16.x", "18.x", "20.x"],
  "features": ["default", "experimental"],
  "include": [
    {
      "os": "windows-latest",
      "node-version": "20.x",
      "features": "default"
    }
  ],
  "exclude": [
    {
      "os": "macos-latest",
      "node-version": "16.x"
    }
  ],
  "strategy": {
    "fail-fast": false,
    "max-parallel": 8
  },
  "max-matrix-size": 256
}
```

### Configuration Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `os` | Array | Yes | Operating systems to test on |
| `node-version` | Array | No | Node.js versions to test with |
| `features` | Array | No | Feature flags for variations |
| `include` | Array | No | Additional matrix entries to include |
| `exclude` | Array | No | Matrix entries to exclude |
| `strategy` | Object | No | GitHub Actions strategy configuration |
| `max-matrix-size` | Number | No | Maximum allowed matrix size (default: 256) |

## Examples

### Simple Single Configuration

```json
{
  "os": ["ubuntu-latest"],
  "node-version": ["18.x"],
  "features": ["default"]
}
```

**Output**:
```json
{
  "matrix": {
    "include": [
      {
        "os": "ubuntu-latest",
        "node-version": "18.x",
        "features": "default"
      }
    ]
  }
}
```

### Multi-OS with Strategy

```json
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node-version": ["18.x", "20.x"],
  "features": ["default"],
  "strategy": {
    "fail-fast": false,
    "max-parallel": 4
  }
}
```

**Output**:
```json
{
  "matrix": {
    "include": [
      { "os": "ubuntu-latest", "node-version": "18.x", "features": "default" },
      { "os": "ubuntu-latest", "node-version": "20.x", "features": "default" },
      { "os": "macos-latest", "node-version": "18.x", "features": "default" },
      { "os": "macos-latest", "node-version": "20.x", "features": "default" }
    ]
  },
  "strategy": {
    "fail-fast": false,
    "max-parallel": 4
  }
}
```

### With Excludes

```json
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node-version": ["16.x", "18.x", "20.x"],
  "features": ["default"],
  "exclude": [
    {
      "os": "macos-latest",
      "node-version": "16.x"
    }
  ]
}
```

Generates 8 combinations (3 OS × 3 versions = 9, minus 1 excluded = 8).

### With Custom Includes

```json
{
  "os": ["ubuntu-latest"],
  "node-version": ["18.x"],
  "features": ["default"],
  "include": [
    {
      "os": "ubuntu-latest",
      "node-version": "18.x",
      "experimental": true,
      "custom-flag": "value"
    }
  ]
}
```

Adds custom entries beyond the cartesian product.

## Integration with GitHub Actions

Use in a workflow to dynamically generate a build matrix:

```yaml
name: Tests
on: [push, pull_request]

jobs:
  generate-matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.generate.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - id: generate
        run: echo "matrix=$(./src/matrix-generator.sh config.json)" >> $GITHUB_OUTPUT

  test:
    runs-on: ubuntu-latest
    needs: generate-matrix
    strategy: ${{ fromJson(needs.generate-matrix.outputs.matrix) }}
    steps:
      - uses: actions/checkout@v4
      - run: echo "Testing on ${{ matrix.os }} with Node ${{ matrix.node-version }}"
```

## Error Handling

### Invalid JSON

```bash
$ matrix-generator.sh invalid.json
Error: invalid JSON in config file: invalid.json
jq: parse error: ...
```

### File Not Found

```bash
$ matrix-generator.sh nonexistent.json
Error: config file not found: nonexistent.json
```

### Matrix Size Exceeded

```bash
$ matrix-generator.sh oversized.json
Error: matrix size (512) exceeds maximum allowed (256)
```

## Testing

### Run Unit Tests

```bash
# Install bats testing framework
apt-get install -y bats

# Run tests
bats tests/test_*.bats
```

### Run Through GitHub Actions (locally with act)

```bash
# Install act (GitHub Actions locally)
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | bash

# Run workflow
act push
```

## Performance Considerations

- **Matrix Size**: Each combination doubles execution time (2 OS × 2 versions × 2 features = 8 jobs)
- **Default Limit**: Maximum 256 combinations to prevent resource exhaustion
- **Parallelization**: Use `max-parallel` strategy to control concurrent job execution

## Contributing

Run tests before submitting changes:

```bash
bats tests/test_*.bats          # Unit tests
shellcheck src/matrix-generator.sh  # Code style
bash -n src/matrix-generator.sh     # Syntax check
actionlint .github/workflows/*.yml  # Workflow validation
```

## License

This tool is provided as-is for use in GitHub Actions workflows.

## Related Documentation

- [GitHub Actions Matrix Strategies](https://docs.github.com/en/actions/using-jobs/using-a-matrix-for-your-jobs)
- [jq Manual](https://stedolan.github.io/jq/manual/)
- [bats Testing Framework](https://github.com/bats-core/bats-core)
