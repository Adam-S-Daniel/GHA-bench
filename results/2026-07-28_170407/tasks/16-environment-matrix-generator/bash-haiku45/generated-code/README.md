# Environment Matrix Generator

A bash script that generates GitHub Actions build matrices from JSON configuration files. Supports cartesian products, include/exclude rules, max-parallel limits, and fail-fast configuration.

## Features

- **Cartesian Product Generation**: Automatically generates all combinations of matrix dimensions
- **Include/Exclude Rules**: Override or filter matrix entries
- **Max Parallel Configuration**: Limit concurrent jobs
- **Fail-Fast Control**: Enable/disable fast failure on first job failure
- **Matrix Size Validation**: Prevent excessively large matrices
- **Comprehensive Error Handling**: Validates JSON and reports meaningful errors

## Usage

```bash
./matrix-generator.sh <config.json>
```

## Configuration

The configuration file is JSON with the following structure:

```json
{
  "os": ["ubuntu-latest", "macos-latest", "windows-latest"],
  "node_version": ["18", "20"],
  "include": [
    {"os": "custom-os", "node_version": "21"}
  ],
  "exclude": [
    {"os": "macos-latest", "node_version": "18"}
  ],
  "max_parallel": 10,
  "fail_fast": true,
  "max_matrix_size": 100
}
```

### Configuration Options

- **Matrix Dimensions** (required): Any top-level keys that are arrays are treated as matrix dimensions. The script generates a cartesian product of all combinations.

- **include** (optional): Array of objects to explicitly include in the matrix. When specified, replaces the cartesian product with these entries.

- **exclude** (optional): Array of objects to filter out from the matrix. Applied after generating the cartesian product (when include is not specified).

- **max_parallel** (optional): Maximum number of concurrent jobs. If omitted, GitHub Actions uses its default.

- **fail_fast** (optional): Boolean flag. Set to `true` to cancel remaining jobs on first failure. Default: `false`.

- **max_matrix_size** (optional): Maximum allowed matrix size. The script exits with error if the generated matrix exceeds this. Default: `100`.

## Output

Outputs a JSON object suitable for GitHub Actions `strategy.matrix`:

```json
{
  "include": [
    {
      "os": "ubuntu-latest",
      "node_version": "18"
    },
    ...
  ],
  "exclude": [
    {
      "os": "macos-latest",
      "node_version": "18"
    }
  ],
  "fail-fast": true,
  "max-parallel": 10
}
```

## Examples

### Basic Example

```bash
cat > config.json <<'EOF'
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node_version": ["18", "20"]
}
EOF

./matrix-generator.sh config.json
```

Output:
```json
{
  "include": [
    {"os": "ubuntu-latest", "node_version": "18"},
    {"os": "ubuntu-latest", "node_version": "20"},
    {"os": "macos-latest", "node_version": "18"},
    {"os": "macos-latest", "node_version": "20"}
  ],
  "exclude": [],
  "fail-fast": false
}
```

### Advanced Example with Include/Exclude

```bash
cat > config.json <<'EOF'
{
  "os": ["ubuntu-latest", "macos-latest"],
  "python_version": ["3.9", "3.11"],
  "include": [
    {"os": "windows-latest", "python_version": "3.11"}
  ],
  "exclude": [
    {"os": "macos-latest", "python_version": "3.9"}
  ],
  "max_parallel": 5,
  "fail_fast": true
}
EOF

./matrix-generator.sh config.json
```

## Error Handling

- **Missing config file**: Exits with status 1, message "Config file not found"
- **Invalid JSON**: Exits with status 1, message "Invalid JSON in <file>"
- **Matrix too large**: Exits with status 1, message "Matrix size (...) exceeds maximum (...)"

## Testing

Run the test suite with:

```bash
bats tests/test_matrix_generator.bats
```

The test suite includes 17 comprehensive tests covering:
- Basic matrix generation
- Cartesian products with multiple dimensions
- Include/exclude functionality
- Configuration options (fail-fast, max-parallel)
- Matrix size validation
- Error handling
- Edge cases (empty dimensions, etc.)

## Validation

The script passes:
- **shellcheck**: Static bash linting
- **bash -n**: Bash syntax validation
- **jq**: JSON output validation

## GitHub Actions Integration

Use in a GitHub Actions workflow:

```yaml
- name: Generate build matrix
  run: |
    ./matrix-generator.sh config.json > matrix.json
    
- name: Use the matrix
  uses: actions/github-script@v6
  with:
    script: |
      const matrix = require('./matrix.json');
      core.setOutput('matrix', JSON.stringify(matrix));
```

Or directly in a matrix strategy:

```yaml
strategy:
  matrix: ${{ fromJSON(needs.generate-matrix.outputs.matrix) }}
```

## Limitations

- Supports up to 4 dimensions for efficient cartesian product generation
- Matrix dimensions are generated deterministically (sorted keys order in jq)
- No support for parameterized dimensions or dynamic configuration
