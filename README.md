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

## Installation
`treedocs` currently supports macOS 13 and newer. Windows and Linux are not supported yet; please open a GitHub issue if you want either platform supported.

GitHub Releases are the canonical release record. Package-manager distribution builds from source instead of shipping prebuilt binaries.

### Swift Package Manager
From a local checkout:

```bash
swift run treedocs --help
```

Or build a release binary:

```bash
swift build -c release
.build/release/treedocs --help
```

### Mint
Install or run the released CLI with Mint:

```bash
mint install DandyLyons/treedocs@0.1.0
mint run DandyLyons/treedocs@0.1.0 --help
```

Mint builds Swift executable packages from source and links installed tools through its configured Mint bin path.

### Homebrew
Homebrew distribution uses the dedicated `DandyLyons/homebrew-tap` repository, which can host formulae for multiple DandyLyons tools.

Install with Homebrew:

```bash
brew install DandyLyons/tap/treedocs
```

Development builds from `main` are also available:

```bash
brew install DandyLyons/tap/treedocs --HEAD
```

### mise
Install the released CLI with mise's Swift Package Manager backend:

```bash
mise use -g spm:DandyLyons/treedocs@0.1.0
```

To track the latest release:

```bash
mise use -g spm:DandyLyons/treedocs
```

mise uses SwiftPM artifact bundles when releases publish them. `treedocs` does not currently ship prebuilt artifact bundles, so mise builds from source.

## Commands
```bash
treedocs init
treedocs sync
treedocs check
treedocs inspect Sources/treedocs --recursive
treedocs update README.md "Project overview"
treedocs update Sources/treedocs/Core --add-reference DOCS/InitialSpecs.md
treedocs ls
treedocs ls Sources/treedocs
treedocs path renderer
```

Run `treedocs --help` for the full command surface.

## Interactive CLI Behavior
Commands with interactive workflows open terminal UI by default when stdin and stdout are attached to a TTY. For example, `treedocs sync` lets you fill missing descriptions before saving when it is run from an interactive terminal.

Use `-n, --non-interactive` to opt out explicitly in scripts or local automation:

```bash
treedocs sync --non-interactive
treedocs sync -n
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
- `schema_version`: the semver treedocs file-format schema version
- `project`: metadata such as `name`, `version`, and `last_updated`
- `overrides`: project-local config overrides
- `signature`: a deterministic structural hash of the scanned tree
- `tree`: the documented filesystem mirror

The YAML format is defined by a canonical JSON Schema so the CLI, tests, editors, CI workflows, and external agents can validate the same structure. Generated files include a managed YAML language-server header comment that points editor tooling at the matching public schema URL. `treedocs` regenerates this header whenever it saves `treedocs.yaml`; arbitrary YAML comments are not preserved.

`schema_version` identifies the `treedocs.yaml` file-format schema and follows semver, such as `0.1.0`. `project.version` is different: it is the documented project's own version and is not used to resolve the treedocs schema.

Directory entries use `_doc` for their description. Entries can also include `references` and `_link`.

YAML comments in `treedocs.yaml`, other than the managed language-server schema header, are not preserved when the CLI loads and rewrites the file. Store durable notes as descriptions or `references` instead of comments.

Example:

```yaml
# yaml-language-server: $schema=https://dandylyons.github.io/treedocs/schemas/0.1.0/treedocs.schema.json
schema_version: "0.1.0"
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

## GitHub Pages
The project site is deployed to `https://dandylyons.github.io/treedocs/` from the static files in `site/`.

GitHub Pages is published by the `Deploy GitHub Pages` workflow in `.github/workflows/pages.yml`. The workflow uses GitHub Actions deployment rather than branch or folder publishing, so Pages configuration and deployment behavior stay version controlled.

The canonical JSON Schema is stored in the public versioned site path at `site/schemas/0.1.0/treedocs.schema.json` and bundled into the CLI for offline validation. The current schema version is tracked as the semver value `CURRENT_TREEDOCS_JSONSCHEMA_VERSION` in `.env.schema` using Varlock syntax. The published schema endpoints are:

- `https://dandylyons.github.io/treedocs/schemas/0.1.0/treedocs.schema.json`
- `https://dandylyons.github.io/treedocs/schemas/latest/treedocs.schema.json`

Versioned schema URLs are immutable after release. The `latest` endpoint is generated by the Pages workflow during deployment and may move forward when a new schema version is released.

Schema release checklist:
- Add the new immutable schema directory, such as `site/schemas/0.2.0/`.
- Update the schema `$id` to the new versioned public URL.
- Update `Package.swift` so the CLI bundles the new versioned schema.
- Update `.env.schema` `CURRENT_TREEDOCS_JSONSCHEMA_VERSION` so `schemas/latest/treedocs.schema.json` is copied from the new schema version.
- Do not edit already-published versioned schema files after release.
- Run `swift build` and focused schema validation tests locally before release.

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
