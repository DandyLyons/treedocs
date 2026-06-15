# Treedocs (TD)
`treedocs` is a CLI tool that generates and maintains a version-controlled, YAML-based architectural map of a repository by mirroring the file system and mapping paths to human-readable descriptions.

> Implementation note: this document remains the design reference for the target API. The current Swift package may differ from this draft while implementation catches up; verify live behavior against the source in `Sources/treedocs/`.

Legend: ✅ implemented; 💬 not yet implemented.
## 1. Overview ✅
`treedocs` is a CLI tool designed to maintain a high-level "map" of a software repository. Unlike a standard `tree` command, `treedocs` maps file paths to human-readable purposes, stored in a version-controlled `treedocs.yaml` file. It serves as "Architectural Documentation as Code."
## 2. Configuration & Hierarchy ✅
`treedocs` settings are managed separately from the documentation state. Settings are merged hierarchically, with local project settings overriding global user settings.
### 2.1 Configuration Files ✅
1. ✅ **Global Config**: `~/.config/treedocs/config.yaml` (User-specific preferences).
2. ✅ **Project Config**: `./.treedocs/config.yaml` (Project-specific rules and logic).
3. ✅ **Project State**: `./treedocs.yaml` (The actual documentation tree and project-specific state).
### 2.2 Configurable Options (config.yaml) ✅
Defined in the `config.yaml` files:
- ✅ **Ignore Patterns**: `exclude`, `use_gitignore`.
- ✅ **Formatting**: `max_description_length`, `indent_size`, `align_columns`.
- ✅ **Severity & Logic**: `check_severity` (`error`/`warn`), `auto_init_empty`.
- ✅ **UI / UX**: `theme`, `icons`.
- ✅ **AI Integration**: `ai_provider`, `ai_model`.
### 2.3 Ignore Logic ✅
`treedocs` respects:
1. ✅ Standard Excludes (`.git`, `node_modules`).
2. ✅ `.gitignore`.
3. ✅ `./.treedocs/.treedocs_ignore`.
### 2.4 Nested `treedocs.yaml` Files ✅
Repositories may contain nested `treedocs.yaml` files. This is intended to work similarly to nested `.git` repositories: each `treedocs.yaml` owns the documentation state for the directory where it lives and that directory's children, unless a deeper child directory contains its own `treedocs.yaml`.

When a child folder has its own `treedocs.yaml`, the child file takes precedence for that subtree. The parent `treedocs.yaml` should still document that the child folder exists, but it should not duplicate or own the child's internal tree. This keeps documentation boundaries aligned with repository, package, or module boundaries and avoids two state files competing over the same paths.

Example:

```text
repo/
├── treedocs.yaml
├── Sources/
└── Vendor/Plugin/
    ├── treedocs.yaml
    └── Sources/
```

In this example, `repo/treedocs.yaml` owns `Sources/` and the `Vendor/Plugin/` folder entry. `repo/Vendor/Plugin/treedocs.yaml` owns `Vendor/Plugin/Sources/` and all other descendants under `Vendor/Plugin/`.

Commands that traverse a tree must discover nested `treedocs.yaml` boundaries before scanning descendants. When a nested boundary is found, parent commands should treat that child folder as a delegated documentation root rather than recursively merging the child's entries into the parent state.
## 3. The `treedocs.yaml` Schema ✅
The `treedocs.yaml` file contains the documentation tree and project-specific metadata. Its structure must be defined by a canonical JSON Schema so editors, CI jobs, tests, the Swift CLI, and future tooling can validate YAML files against the same contract.
### 3.1 Root Level Keys ✅
- ✅ **`project`**: Metadata about the repository (e.g., name, version, maintainer).
- ✅ **`overrides`**: Local documentation rules that override the global `config.yaml` for this specific repository.
- ✅ **`signature`**: A system-generated checksum or state-hash used to detect drift quickly during `check`.
- ✅ **`tree`**: The nested object representing the file system hierarchy.
### 3.2 Canonical Schema ✅
- ✅ The canonical schema lives at `DOCS/treedocs.schema.json`.
- ✅ Validation runs against parsed YAML data, not raw YAML text. `treedocs.yaml` remains the user-facing format, while JSON Schema defines the structural contract.
- ✅ The schema covers root keys, project metadata, override values, signature format, tree entry variants, reserved keys (`_doc`, `_link`), descriptions, and references.
- ✅ The schema must remain usable outside the Swift CLI by editors, CI, and other agents.
### 3.3 CLI Validation ✅
`treedocs check` performs three validations:
1. ✅ It validates `treedocs.yaml` against `DOCS/treedocs.schema.json`.
2. ✅ It compares `treedocs.yaml` against the repository's actual folder structure and highlights discrepancies.
3. ✅ It discovers nested `treedocs.yaml` files and reports when a parent `treedocs.yaml` is contradicted by a child `treedocs.yaml` for a subtree.

The repository folder structure is the source of truth, with nested `treedocs.yaml` files acting as documentation boundaries. `check` exists to identify where `treedocs.yaml` is stale, invalid, incomplete, or shadowed by a more specific child state file so the documentation tree can be updated to match the filesystem. If schema validation fails, `check` reports the validation errors and exits according to the configured `check_severity`.

Implementation direction: parse `treedocs.yaml` with `Yams`, convert the parsed value into JSON-compatible data, and validate it with the Swift dependency `ajevans99/swift-json-schema`.

Validation tests should verify that:
- ✅ Every `treedocs.yaml` file produced by the CLI conforms to the schema.
- ✅ Invalid `treedocs.yaml` fixtures are rejected.
- ✅ Validation failures include informative errors that identify the invalid field or path.
- ✅ Nested `treedocs.yaml` files take precedence over parent files for their subtree.
- ✅ `check` reports when a parent tree attempts to document paths owned by a child `treedocs.yaml`.
### 3.4 Tree Value Types ✅
To support both simple and deep documentation, a path's value in the `tree` can be:
1. ✅ **A String**: For simple, one-line descriptions.
2. ✅ **An Object**: For detailed documentation.
    - ✅ `description`: (Optional) The primary purpose string.
    - ✅ `references`: (Optional) A list of local paths or `https://` URLs for supplementary info, or markdown links (`[example](https://example.com)`).
    - ✅ `_doc`: (Reserved for folders) Description for the directory itself.
    - ✅ `_link`: (Reserved) Internal or External alias/redirect.
### 3.5 Example Structure ✅
```yaml
project:
  name: "ScraperBot"
  version: "2.1.0"
  last_updated: "2023-10-27"
overrides:
  check_severity: "error"
  icons: true
signature: "sha256:7a8b9c0d1e2f34567890abcdef1234567890abcdef1234567890abcdef123456"
tree:
  src:
    _doc: "Main application source code"
    api:
      _doc: "REST endpoint definitions"
      auth.py: "Handles JWT validation and user sessions"
  Database:
    _doc:
      description: "Data persistence layer and migration scripts"
      references:
        - "DOCS/Database.md"
        - "DOCS/Schema.md"
        - "https://wiki.internal.com/db-standards"
  docs/architecture:
    _link: "src/api"
    _doc: "Alias to API folder for architectural reference"
  README.md: "Project entry point and installation guide"
```
### 3.6 Known Limitations ✅
- ✅ **Comments are not preserved**: `Yams` does not preserve YAML comments during load and re-serialization. `treedocs` will not implement custom YAML comment parsing, so users should avoid comments in `treedocs.yaml` and express durable notes as descriptions or references instead. The schema should preserve this expressiveness by providing structured places for user-authored documentation.

## 4. Command Definitions ✅
### 4.1 `treedocs init` ✅
Walks the file system and generates a `treedocs.yaml`. It populates the `tree` key, generates an initial `signature`, and initializes `project.name`, `project.version`, and `project.last_updated`.
### 4.2 `treedocs sync` ✅
Reconciles disk state with the `tree` key.
- ✅ **Signature Update**: Recalculates and updates the `signature` key after a successful sync.
- ✅ `--interactive`: Prompt for descriptions of new files.
- ✅ **Nested Boundaries**: Stops recursive ownership at child folders that contain their own `treedocs.yaml` and preserves those folders as delegated documentation roots.
### 4.3 `treedocs check` ✅
Non-interactive validation with three responsibilities:
1. ✅ Validates `treedocs.yaml` against the canonical JSON Schema.
2. ✅ Compares `treedocs.yaml` against the current repository folder structure, treating the folder structure as the source of truth.
3. ✅ Reports nested `treedocs.yaml` boundaries where child documentation state takes precedence over parent documentation state.

`check` reports schema errors, missing paths, extra documented paths, signature drift, missing descriptions, and child `treedocs.yaml` precedence boundaries. When a parent `treedocs.yaml` documents paths beneath a child `treedocs.yaml`, `check` should inform the user that those descendant paths are shadowed by the child state file and identify the affected subtree. It returns exit code `1` when the documentation tree is invalid, stale, or incomplete. (The user can configure which conditions trigger a failure exit code 1 and which are warnings exit code 0). 
### 4.4 `treedocs show` ✅
`treedocs show <path>` is the canonical command for viewing a documented path. It shows the tree rooted at `path` with inline descriptions, similar to the standard `tree` command, while resolving links and showing associated `references` when requested by output options.

`show` always runs the same validation used by `treedocs check` under the hood before rendering. If validation finds schema errors, missing paths, extra documented paths, signature drift, missing descriptions, or nested `treedocs.yaml` boundary issues, `show` should still render the best available documentation tree and print a warning to stdout. The warning should summarize that discrepancies were found and prompt the user to run `treedocs check` for the full diagnostic report. (The user can skip automatic checks with `--no-check` or with configuration). 

`treedocs <path>` is an alias for `treedocs show <path>` and should produce the same output. The implementation should share one renderer and command path so aliases cannot drift in behavior.

Example:

```text
$ treedocs show Sources/treedocs/Core
Sources/treedocs/Core - Core services used by the CLI commands
├── ConfigLoader.swift - Loads and merges global and project configuration
├── DescriptionFormatter.swift - Formats descriptions for aligned tree output
├── IgnoreMatcher.swift - Applies standard excludes, gitignore rules, and treedocs ignore rules
├── LinkResolver.swift - Resolves _link chains for show output
├── Scanner.swift - Scans the repository filesystem into a documentation tree
└── Signature.swift - Generates deterministic hashes for drift detection
```
### 4.5 `treedocs update` ✅
>[!LOW PRIORITY]
>This command is low priority because the `treedocs.yaml` file can be edited directly by hand or by an AI agent. 

`treedocs update <path> "<description>"` modifies the entry inside the `tree` key and updates the `signature`.

> ✅ The current CLI also supports reference and link mutation flags:
>- `--add-reference`
>- `--remove-reference`
>- `--link`
>- `--clear-link`
### 4.6 `treedocs config show` ✅
`treedocs config show <path>` shows all treedocs-related files recursively under the folder at `path`. This is a discovery command for configuration and state files, including nested `treedocs.yaml` files, `.treedocs/config.yaml`, `.treedocs/.treedocs_ignore`, and other files reserved for treedocs metadata.

Example:

```text
$ treedocs config show .
treedocs.yaml
.treedocs/config.yaml
.treedocs/.treedocs_ignore
Vendor/Plugin/treedocs.yaml
```
### 4.7 `treedocs prompts` ✅
Generates copyable prompts that help humans and AI agents maintain `treedocs.yaml` without requiring the CLI to call an AI provider directly.

#### 4.7.1 `treedocs prompts fill` ✅
Creates a string prompt asking an agent to intelligently fill in missing descriptions in `treedocs.yaml`.

The generated prompt should instruct the agent to:
- ✅ Read the repository structure and the existing `treedocs.yaml`.
- ✅ Preserve existing descriptions, references, links, project metadata, and valid schema structure unless a change is necessary to fix an inconsistency.
- ✅ Fill missing descriptions with concise, accurate explanations based on source files, neighboring paths, names, imports, tests, and documentation.
- ✅ Ask the user clarifying questions for unclear paths instead of inventing uncertain descriptions.
- ✅ Update `treedocs.yaml` only after unclear details have been resolved or explicitly marked as needing user input.
- ✅ Keep the result valid against `DOCS/treedocs.schema.json`.

The command writes the prompt to stdout. It does not modify `treedocs.yaml` itself.
## 5. Advanced Features
### 5.1 Alias (`ln`) & External Handling ✅
Supports internal relative links and external URLs via the `_link` key.
### 5.2 Documentation Templates 💬
Defined in `.treedocs/config.yaml` to automatically document files matching specific patterns.
### 5.3 Shell Integration ✅
Search-based navigation: `cd $(treedocs path <query>)`.

> ✅ The current implementation matches against both normalized paths and entry descriptions and returns a single raw path on success.
## 6. What Makes `treedocs` Unique? ✅
### 6.1 Strict Filesystem Mirroring ✅
Maintains a 1:1 structural mirror of the repository, preventing the "map" from drifting from reality.
### 6.2 Collaborative Human-LLM Maintenance ✅
`treedocs init` creates a `treedocs.yaml` that is a recursive tree in YAML form, with empty descriptions. These descriptions can be filled in by an LLM or by a human, making it easy for humans to refine or correct the architectural intent.
### 6.3 Detecting Architectural Drift ✅
Acts as a sentinel that fails when the YAML state no longer matches the filesystem reality, reducing cognitive load for understanding structural shifts.
## 7. Use Cases ✅
1. ✅ **Onboarding**: Instant repository overview via `treedocs show .`.
2. ✅ **Maintenance**: Quick updates via `treedocs update`.
3. ✅ **Governance**: CI enforcement via `treedocs check`.
## 8. Influences & Similar Tools
### 8.1 AI Repository Mappers 💬
- [**RepoMapper**](https://github.com/pdavis68/RepoMapper "null")
- [**Repository Intelligence Graph (RIG)**](https://github.com/Greenfuze/Spade "null")
### 8.2 Enhanced Navigation & Tree Utilities 💬
- [**broot**](https://github.com/Canop/broot "null")
### 8.3 Continuous Documentation 💬
- [**brief**](https://github.com/git-pkgs/brief "null"): A major influence that provides objective truth repo info like toolchains, programming languages used, testing frameworks, CI pipelines, etc.
- [**Swimm**](https://swimm.io/ "null")
- [**DocWeave**](https://dev.to/julsr_mx/cli-tool-that-analyzes-git-repos-and-generates-beautiful-documentation-4e47 "null")
## 9. Future Directions
### 9.1 Model Context Protocol (MCP) Integration 💬
Exposes `show` and `config show` as standardized JSON-RPC methods for AI IDEs.
### 9.2 Agent Skill / Toolset 💬
Helps agents identify relevant architectural layers to save tokens in context windows.
