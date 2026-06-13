# treedocs

## Project Brief
- **Language**: Swift 6.0 (SPM)
- **Platform**: macOS 13+
- **CLI framework**: apple/swift-argument-parser
- **YAML Parsing**: jpsim/Yams
- **Schema Contract**: `treedocs.yaml` should be defined by JSON Schema
- **Filepath Utilities**: kylef/PathKit
- **Hashing**: CryptoKit
- **Testing**: Swift Testing (`import Testing`), not XCTest
- **Build check**: use `swift build`

## Commands
```bash
swift build
swift run treedocs --help
swift run treedocs init --help
swift test
swift test --filter "Workflow"
swift test --filter "Schema and Config"
swift test --filter "Scanner and Signature"
swift test --filter "IgnoreMatcher"
```

## GitHub
- Use the `DandyLyons` GitHub account for this repository before running `gh` commands: `gh auth switch --user DandyLyons`

## Architecture
- Executable entry point: `Sources/treedocs/TreeDocs.swift`
- CLI commands live in `Sources/treedocs/Commands/`
- Core services live in `Sources/treedocs/Core/`
- Data models live in `Sources/treedocs/Models/`
- Tests live in `Tests/treedocsTests/`

## Implemented CLI Surface
- Root subcommands: `init`, `sync`, `check`, `inspect`, `update`, `ls`, `path`
- Shared repository option: `-p, --path <path>`
- `init` writes `treedocs.yaml` with project metadata, signature, and empty descriptions
- `sync` preserves existing metadata while reconciling filesystem changes
- `check` reports signature drift and missing descriptions, and respects configured severity
- `inspect` resolves `_link` chains and can render a subtree recursively
- `update` supports description changes plus `--add-reference`, `--remove-reference`, `--link`, and `--clear-link`
- `ls` renders the documentation tree and supports subtree rendering with an optional positional path argument
- `path` searches both documented paths and descriptions
- Scanner-backed commands stop at nested `treedocs.yaml` files: the parent keeps the child folder as a delegated directory entry and does not own descendants beneath that boundary

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
