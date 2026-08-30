[![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

# treedocs

`treedocs` is a Swift CLI that keeps a version-controlled architectural map of a repository in `treedocs.yaml`. It mirrors the filesystem, stores human-readable descriptions, and helps detect documentation drift.

## What It Does
- Scans a repository into a nested YAML tree
- Treats nested `treedocs.yaml` files as documentation boundaries for delegated subtrees
- Stores project metadata, documentation, references, and internal links
- Defines the `treedocs.yaml` contract with JSON Schema for reusable validation
- Reconciles disk changes back into the YAML state
- Imports folder and README-file documentation from `README.md` YAML frontmatter
- Fails CI-style checks when the tree is stale or descriptions are missing
- Renders a documented tree and resolves links for inspection
- Finds relevant paths from a query for shell workflows

## Installation
`treedocs` currently supports macOS 13 and newer. Windows and Linux are not supported yet; please open a GitHub issue if you want either platform supported.

GitHub Releases are the canonical release record. Package-manager distribution builds from source instead of shipping prebuilt binaries, so installing through Homebrew, Mint, or mise requires a Swift 6.2-capable build environment.

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
mint install DandyLyons/treedocs@0.2.0
mint run DandyLyons/treedocs@0.2.0 --help
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
MISE_EXPERIMENTAL=true mise use -g spm:DandyLyons/treedocs@0.2.0
```

To track the latest release:

```bash
MISE_EXPERIMENTAL=true mise use -g spm:DandyLyons/treedocs
```

mise uses SwiftPM artifact bundles when releases publish them. `treedocs` does not currently ship prebuilt artifact bundles, so mise builds from source. The mise `spm:` backend is currently experimental, so set `MISE_EXPERIMENTAL=true` when installing.

## Commands
```bash
treedocs init
treedocs sync
treedocs check
treedocs inspect Sources/treedocs --recursive
treedocs update README.md "Project overview"
treedocs update Sources/treedocs/Core --add-reference DOCS/schema-cli-usage.md
treedocs createREADME Sources/treedocs/Core/
treedocs createREADME Sources/ --recursive
treedocs show . --full-descriptions
treedocs explore Sources/ --full-descriptions
treedocs ls
treedocs ls Sources/treedocs
treedocs path renderer
```

`show` and `explore` truncate long descriptions by default. Use `--full-descriptions` or `-f` to render complete descriptions for files and folders.

Run `treedocs --help` for the full command surface.

## Interactive CLI Behavior
Commands with interactive workflows open terminal UI by default when stdin and stdout are attached to a TTY. For example, `treedocs sync` lets you fill missing descriptions before saving when it is run from an interactive terminal.

Use `-n, --non-interactive` to opt out explicitly in scripts or local automation:

```bash
treedocs sync --non-interactive
treedocs sync -n
```

Non-TTY contexts, such as CI and redirected input/output, skip interactive UI automatically.

## README Frontmatter

`treedocs init` and `treedocs sync` discover exact `README.md` filenames through the normal scanner, so ignore rules and nested `treedocs.yaml` boundaries still apply. A nested README can document both its containing folder and the README file:

```markdown
---
description: Core scanning and reconciliation logic.
references:
  - ../../DOCS/architecture.md
readme:
  description: How the core implementation is organized.
  references:
    - "[Architecture](../../DOCS/architecture.md)"
---

# Core
```

Top-level `description` and `references` describe the containing folder. Values under `readme` describe the `README.md` file itself. Local references are resolved relative to the README's folder; HTTPS URLs are preserved. Other frontmatter keys and the Markdown body are retained when treedocs updates supported metadata.

The repository-root README can document its own file through `readme.*`. Root-folder documentation is deferred because the current `0.2.0` tree format has no root `_doc` entry; top-level folder fields there produce a non-failing warning. `_link` is not imported from README frontmatter.

When README and `treedocs.yaml` values differ, interactive sync asks which value to keep. Non-interactive sync reports all conflicts, writes nothing, and exits nonzero. `treedocs check` reports pending imports and conflicts without modifying either file. A recognized README without a usable `readme.description` receives a sensible file-description default in `treedocs.yaml`; treedocs-only values are not automatically copied into README frontmatter.

### Create README Stubs

Materialize existing directory documentation from `treedocs.yaml` as a structured README stub:

```bash
treedocs createREADME Sources/treedocs/Core/
treedocs createREADME Sources/ --recursive
```

`createREADME` copies a documented nested folder's non-blank description and de-duplicated references into top-level frontmatter, makes local references relative to the generated README, and always adds a deterministic `readme.description` plus a level-one directory heading. A root README uses the project name and only `readme.*` metadata because the current schema has no root-folder `_doc`.

Recursive creation includes the requested directory, respects the standard excludes and configured ignore files, and stops below nested `treedocs.yaml` boundaries. Existing exact `README.md` files are skipped without being read or changed. All output is rolled back if a later creation fails, `treedocs.yaml` remains unchanged, and the command recommends `treedocs sync` after it creates files.

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

`schema_version` identifies the `treedocs.yaml` file-format schema and follows semver, such as `0.2.0`. `project.version` is different: it is the documented project's own version and is not used to resolve the treedocs schema.

Directory entries use `_doc` for their description. Object-form metadata uses `_description` and `_references`. Entries can also include `_link`. Compact string descriptions are still valid.

YAML comments in `treedocs.yaml`, other than the managed language-server schema header, are not preserved when the CLI loads and rewrites the file. Store durable notes as descriptions or `references` instead of comments.

Example:

```yaml
# yaml-language-server: $schema=https://dandylyons.github.io/treedocs/schemas/0.2.0/treedocs.schema.json
schema_version: "0.2.0"
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
          _description: Core scanning, rendering, and config logic
          _references:
            - DOCS/schema-cli-usage.md
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

The canonical JSON Schema is stored in the public versioned site path at `site/schemas/0.2.0/treedocs.schema.json` and bundled into the CLI for offline validation. The current schema version is tracked as the semver value `CURRENT_TREEDOCS_JSONSCHEMA_VERSION` in `.env.schema` using Varlock syntax. The published schema endpoints are:

- `https://dandylyons.github.io/treedocs/schemas/0.2.0/treedocs.schema.json`
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

## md-utils
[`md-utils`](https://github.com/DandyLyons/md-utils) is a sister project maintained and designed by the same author. Where `treedocs` tracks repository structure and path-level documentation, `md-utils` provides a Swift library, CLI, and Agent Skill for parsing, querying, and rewriting Markdown files.

The two tools are designed to complement each other, and planned integration will connect `treedocs` repository maps with `md-utils` Markdown operations.
