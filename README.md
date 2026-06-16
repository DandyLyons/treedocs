# treedocs

`treedocs` is a Swift CLI that keeps a version-controlled architectural map of a repository in `treedocs.yaml`. It mirrors the filesystem, stores human-readable descriptions, and helps detect documentation drift.

## What It Does
- Scans a repository into a nested YAML tree
- Treats nested `treedocs.yaml` files as documentation boundaries for delegated subtrees
- Stores project metadata, documentation, references, and internal links
- Defines the `treedocs.yaml` contract with JSON Schema for reusable validation
- Reconciles disk changes back into the YAML state
- Fails CI-style checks when the tree is stale or descriptions are missing
- Renders a documented tree and resolves links for inspection
- Finds relevant paths from a query for shell workflows

## Commands
```bash
swift run treedocs init
swift run treedocs sync
swift run treedocs check
swift run treedocs inspect Sources/treedocs --recursive
swift run treedocs update README.md "Project overview"
swift run treedocs update Sources/treedocs/Core --add-reference DOCS/InitialSpecs.md
swift run treedocs ls
swift run treedocs ls Sources/treedocs
swift run treedocs path renderer
```

Run `swift run treedocs --help` for the full command surface.

## Interactive CLI Behavior
Commands with interactive workflows open terminal UI by default when stdin and stdout are attached to a TTY. For example, `treedocs sync` lets you fill missing descriptions before saving when it is run from an interactive terminal.

Use `-n, --non-interactive` to opt out explicitly in scripts or local automation:

```bash
swift run treedocs sync --non-interactive
swift run treedocs sync -n
```

Non-TTY contexts, such as CI and redirected input/output, skip interactive UI automatically.

## Git Commit Hook
`treedocs` can run from a Git `pre-commit` hook so commits stop when `treedocs.yaml` is stale or incomplete. This repository vends a suggested hook at `contrib/hooks/pre-commit`; users are responsible for reviewing and installing it in their own repositories.

Install the suggested hook for the current repository:

```bash
install -m 755 contrib/hooks/pre-commit .git/hooks/pre-commit
```

The hook runs:

```bash
treedocs sync --non-interactive
```

`treedocs sync --non-interactive` reconciles fixable filesystem drift without opening terminal UI. If sync changes `treedocs.yaml`, the hook stops the commit so you can review and stage the updated state:

```bash
git add treedocs.yaml
git commit
```

`treedocs sync` also reports remaining issues such as missing descriptions after reconciliation. Git hooks block commits when a command exits non-zero; treedocs validation commands use non-zero exits for blocking issues when `check_severity` resolves to `error`, which is the default.

Set `TREEDOCS_BIN` if the executable is not available as `treedocs` on `PATH`:

```bash
TREEDOCS_BIN=/path/to/treedocs git commit
```

## Color Output
`treedocs` uses Rainbow for ANSI-styled terminal output. Rainbow enables colors for supported TTY output and returns plain text for unknown output targets, such as most redirected output.

Rainbow also respects standard color environment controls: set `NO_COLOR` to disable color output, or `FORCE_COLOR` to force color output. `treedocs` does not currently provide a dedicated `--no-color` flag.

## treedocs.yaml Shape
`treedocs.yaml` contains:
- `project`: metadata such as `name`, `version`, and `last_updated`
- `overrides`: project-local config overrides
- `signature`: a deterministic structural hash of the scanned tree
- `tree`: the documented filesystem mirror

The YAML format should be defined by a canonical JSON Schema so the CLI, tests, editors, CI workflows, and external agents can validate the same structure.

Directory entries use `_doc` for their description. Entries can also include `references` and `_link`.

YAML comments in `treedocs.yaml` are not preserved when the CLI loads and rewrites the file. Store durable notes as descriptions or `references` instead of comments.

Example:

```yaml
project:
  name: treedocs
  version: 0.0.0
  last_updated: 2026-04-30
signature: sha256:...
tree:
  Sources:
    _doc: Source files for the CLI
    treedocs:
      Core:
        _doc:
          description: Core scanning, rendering, and config logic
          references:
            - DOCS/InitialSpecs.md
  README.md: Project overview
```

## Configuration
Configuration is merged in this order:
1. Built-in defaults
2. `~/.config/treedocs/config.yaml`
3. `.treedocs/config.yaml`
4. `treedocs.yaml` `overrides`

Supported config areas include:
- Ignore behavior: `exclude`, `use_gitignore`
- Rendering: `max_description_length`, `indent_size`, `align_columns`
- Validation: `check_severity`, `auto_init_empty`
- UI/metadata: `theme`, `icons`, `ai_provider`, `ai_model`

Ignore sources are combined from:
- Standard excludes such as `.git`, `.build`, `.swiftpm`, `.treedocs`, `.agents`, `.opencode`, and `node_modules`
- `.gitignore`
- `.treedocs/.treedocs_ignore`

## Nested Documentation Boundaries
When a child folder contains its own `treedocs.yaml`, that file owns documentation for the child folder's descendants. The parent scan still records the child folder as a directory, but it does not recursively include the child's files or subdirectories.

For example, if `Vendor/Plugin/treedocs.yaml` exists, the parent `treedocs.yaml` owns `Vendor/Plugin/` as a delegated directory entry while `Vendor/Plugin/treedocs.yaml` owns `Vendor/Plugin/Sources/` and other descendants.

## Development
```bash
swift build
swift test
swift test --filter "Workflow"
swift test --filter "Schema and Config"
swift test --filter "Scanner and Signature"
swift test --filter "IgnoreMatcher"
```

Source layout:
- `Sources/treedocs/Commands/`: CLI subcommands
- `Sources/treedocs/Core/`: services and filesystem logic
- `Sources/treedocs/Models/`: YAML and config models
- `Tests/treedocsTests/`: Swift Testing suites
