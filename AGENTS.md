# treedocs

## Project Brief
- **Language**: Swift 6.2 (SPM)
- **Platform**: macOS 13+
- **CLI framework**: apple/swift-argument-parser
- **Interactive CLI UX**: tuist/Noora
- **YAML Parsing**: jpsim/Yams
- **Markdown/frontmatter parsing**: DandyLyons/md-utils (`MarkdownUtilitiesCore`)
- **Schema Contract**: `treedocs.yaml` should be defined by JSON Schema
- **Filepath Utilities**: kylef/PathKit
- **Hashing**: CryptoKit
- **Testing**: Swift Testing (`import Testing`), not XCTest
- **Build check**: use `swift build`

## Commands
```bash
swift build
swift run treedocs --help # shows root command help
swift run treedocs init # initializes treedocs.yaml
swift run treedocs sync # syncs treedocs.yaml with filesystem changes
swift run treedocs sync --populate-docs children # copies immediate child descriptions into recognized documentation sources
swift run treedocs sync --populate-docs recursive # copies all owned descendant descriptions into recognized documentation sources
swift run treedocs createDoc Sources/ # creates the selected documentation source for Sources/
swift run treedocs createDoc Sources/ --recursive # creates stubs in eligible descendant directories
swift run treedocs show . # shows the documentation tree for the current directory
swift run treedocs explore . # shows only top-level files and folders with descriptions
swift run treedocs explore ./subfolder/ ./subfolder2/ # expands the selected folders while all others are collapsed
swift test
swift test --filter "Workflow"
swift test --filter "Schema and Config"
swift test --filter "Scanner and Signature"
swift test --filter "IgnoreMatcher"
```

## Security
- Never use `npx`; it can execute unpinned remote packages and is not allowed in this repository.
- Use the installed `varlock` binary directly for Varlock commands, for example `varlock printenv CURRENT_TREEDOCS_JSONSCHEMA_VERSION`.

## Release Work
- Before making or preparing any release-related change, read and follow `.agents/skills/releasing-treedocs/SKILL.md`.
- Do not edit release-related files or state until the skill's required complete reading of `DOCS/Release Strategy.md` is finished.
- Release-related work includes CLI and JSON Schema versions, release documentation and site content, tags, GitHub Releases, GitHub Pages publication, checksums, Homebrew formulae and tap updates, Mint and mise instructions, and release automation.

## Codebase Exploration
- Always invoke the CLI from this checkout with `swift run treedocs` so SwiftPM builds and runs the latest source. Do not rely on a plain `treedocs` command or a previously built binary.
- When you need to explore or understand the codebase, run `swift run treedocs explore` first. It immediately generates a tree explanation of the repository's files and folders.
  - Tip: Use `swift run treedocs show <path>` to focus on a specific subtree

## Path Conventions
- Use explicit trailing slashes for all paths that refer to directories, including examples, documentation, config snippets, and CLI help text. Bare `.`, `..`, and `~` are exceptions and do not need trailing slashes.

## Architecture
- Executable entry point: `Sources/treedocs/TreeDocs.swift`
- CLI commands live in `Sources/treedocs/Commands/`
- Core services live in `Sources/treedocs/Core/`
- Data models live in `Sources/treedocs/Models/`
- Tests live in `Tests/treedocsTests/`

## Implemented CLI Surface
- `createDoc` creates the selected documentation source; `createREADME` remains an alias. `sync --populate-docs` retains `--populate-readmes` as an alias.
- Opt-in schema `0.3.0-WIP` supports `overrides.documentation_sources` with exact folder keys (`.` for root, otherwise trailing `/`) and filename values. `README.md` remains the implicit default without inheritance. New source stubs use `file:` metadata; legacy `readme:` remains supported, and conflicting dual mappings are errors.
- Root subcommands: `init`, `sync`, `check`, `show`, `inspect`, `update`, `createREADME`, `config`, `prompts`, `ls`, `explore`, `path`
- Shared repository option: `-p, --path <path>`
- Shared interactive opt-out: `--non-interactive`
- `init` writes `treedocs.yaml` with project metadata, signature, and empty descriptions
- `show` renders the documentation tree for a given path, defaulting to the current directory
- `sync` preserves existing metadata while reconciling filesystem changes and sparse recursive `README.md` frontmatter; `--populate-readmes children|recursive` explicitly copies missing canonical descriptions into recognized README trees
- `check` reports signature drift and missing descriptions, and respects configured severity
- `inspect` resolves `_link` chains and can render a subtree recursively
- `update` supports description changes plus `--add-reference`, `--remove-reference`, `--link`, and `--clear-link`
- `createREADME` creates structured README stubs from stored directory metadata, supports `-r, --recursive`, skips existing exact `README.md` files, and leaves `treedocs.yaml` unchanged
- `ls` renders the documentation tree and supports subtree rendering with an optional positional path argument
- `path` searches both documented paths and descriptions
- Scanner-backed commands stop at nested `treedocs.yaml` files: the parent keeps the child folder as a delegated directory entry and does not own descendants beneath that boundary

## Interactive CLI Convention
- Commands with interactive behavior should default to interactive UI when stdin and stdout are attached to a suitable TTY
- Non-TTY contexts must behave non-interactively automatically, even without `--non-interactive`
- `-n, --non-interactive` is the canonical shared opt-out flag for scripts, CI, and explicit automation
- Do not use `-i` for non-interactive mode because users commonly understand it as `--interactive`

## Reading Dependency Docs
### Noora 
- `https://noora.tuist.dev/sitemap.xml`
- Convert Noora docs pages to Markdown with `https://defuddle.md/<host>/<path>` 
- Example conversion: `https://defuddle.md/noora.tuist.dev/components/alerts/error`

## Schema Notes
- `treedocs.yaml` requires a canonical JSON Schema definition for editor, CI, test, and external tooling validation
- `treedocs.yaml` root keys: `project`, `overrides`, `signature`, `tree`
- `project` is modeled metadata with `name`, `version`, and `last_updated`
- Directory documentation is stored under `_doc`
- Links are stored under `_link`
- Leaf entries may be a simple string or a mapping with `description` and `references`

## Quirks
- `.git`, `.build`, `.swiftpm`, `.treedocs`, `.agents`, `.opencode`, `node_modules`, and `treedocs.yaml` are treated as standard excludes by the scanner
- Ignore loading merges `exclude`, `.gitignore`, and `.treedocs/.treedocs_ignore`, including negation patterns
- A `treedocs.yaml` inside a child directory marks a nested documentation boundary before descendant scanning; do not duplicate that subtree in the parent state
- Local sandboxed `swift run` or `swift test` calls may fail if SwiftPM cannot write its user cache; Solo-managed `swift build` and `swift test` processes are the reliable verification path in this repo
- Build artifacts live in `.build/`
- `solo.yml` defines Solo command processes for `swift build`, `swift test`, and `swift run`
