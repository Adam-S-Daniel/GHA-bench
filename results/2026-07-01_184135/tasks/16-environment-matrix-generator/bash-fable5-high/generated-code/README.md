# Environment Matrix Generator

A Bash tool that turns a declarative configuration (OS options, language
versions, feature flags) into a JSON document suitable for a GitHub Actions
`strategy` block — including `matrix` with `include`/`exclude` rules,
`max-parallel`, and `fail-fast` — and validates that the matrix does not
exceed a maximum size.

## Usage

```console
$ ./matrix-gen.sh --config config.json            # pretty JSON
$ ./matrix-gen.sh --config config.json --compact  # one line, for $GITHUB_OUTPUT
$ ./matrix-gen.sh < config.json                   # read config from stdin
$ ./matrix-gen.sh --config config.json --max-size 32
```

### Configuration format

```json
{
  "os": ["ubuntu-latest", "macos-latest"],
  "language-versions": ["3.11", "3.12"],
  "feature-flags": ["standard"],
  "include": [ { "os": "ubuntu-latest", "language-version": "3.13", "feature-flag": "experimental" } ],
  "exclude": [ { "os": "macos-latest", "language-version": "3.11" } ],
  "max-parallel": 3,
  "fail-fast": false,
  "max-size": 50
}
```

The three axes (`os`, `language-versions`, `feature-flags`) are required
non-empty arrays of strings; everything else is optional. `fail-fast`
defaults to `true` and `max-size` to 256 (both matching GitHub Actions'
own defaults/limits); `max-parallel` is omitted from the output unless
configured. `--max-size` on the command line overrides the config value.

### Size validation

The effective job count mirrors GitHub's expansion rules: the cartesian
product of the three axes, minus combinations matched by `exclude` rules
(partial rules match broadly), plus `include` entries whose axis values
match no surviving combination. If that count exceeds the limit the script
fails with `matrix size N exceeds maximum allowed size M`.

## Development

Built test-first (red/green TDD) with [bats-core](https://github.com/bats-core/bats-core):

```console
$ bats test/              # unit tests + workflow structure tests
$ shellcheck matrix-gen.sh run_act_tests.sh
```

## CI pipeline

`.github/workflows/environment-matrix-generator.yml` runs three chained jobs:

1. **unit_tests** — installs bats and runs the unit suite,
2. **generate_matrix** — runs `matrix-gen.sh` against `config.json` and
   publishes the strategy JSON as job outputs,
3. **build** — consumes the generated matrix via `fromJSON`, proving the
   output is a valid dynamic `strategy.matrix`.

`./run_act_tests.sh` executes every test case end-to-end through the
workflow with [nektos/act](https://github.com/nektos/act), appending all
output to `act-result.txt` and asserting exact expected values and job
success for each case.
