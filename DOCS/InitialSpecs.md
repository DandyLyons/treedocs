# Treedocs (TD)
`treedocs` is a CLI tool that generates and maintains a version-controlled, YAML-based architectural map of a repository by mirroring the file system and mapping paths to human-readable descriptions.

> Implementation note: this document remains the design reference. The current Swift package implements the root subcommands `init`, `sync`, `check`, `inspect`, `update`, `ls`, and `path`, plus config loading, ignore matching, signature generation, link resolution, and Swift Testing coverage. Where the live CLI differs from this draft, prefer the source in `Sources/treedocs/`.
## 1. Overview
`treedocs` is a CLI tool designed to maintain a high-level "map" of a software repository. Unlike a standard `tree` command, `treedocs` maps file paths to human-readable purposes, stored in a version-controlled `treedocs.yaml` file. It serves as "Architectural Documentation as Code."
## 2. Configuration & Hierarchy
`treedocs` settings are managed separately from the documentation state. Settings are merged hierarchically, with local project settings overriding global user settings.
### 2.1 Configuration Files
1. **Global Config**: `~/.config/treedocs/config.yaml` (User-specific preferences).
2. **Project Config**: `./.treedocs/config.yaml` (Project-specific rules and logic).
3. **Project State**: `./treedocs.yaml` (The actual documentation tree and project-specific state).
### 2.2 Configurable Options (config.yaml)
Defined in the `config.yaml` files:
- **Ignore Patterns**: `exclude`, `use_gitignore`.
- **Formatting**: `max_description_length`, `indent_size`, `align_columns`.
- **Severity & Logic**: `check_severity` (`error`/`warn`), `auto_init_empty`.
- **UI / UX**: `theme`, `icons`.
- **AI Integration**: `ai_provider`, `ai_model`.
### 2.3 Ignore Logic
`treedocs` respects:
1. Standard Excludes (`.git`, `node_modules`).
2. `.gitignore`.
3. `./.treedocs/.treedocs_ignore`.
## 3. The `treedocs.yaml` Schema
The `treedocs.yaml` file contains the documentation tree and critical project-specific metadata.

Requirement: the `treedocs.yaml` format must be defined by a JSON Schema so editors, CI jobs, tests, and future tooling can validate the YAML document against the same structural contract.
### 3.1 Root Level Keys
- **`project`**: Metadata about the repository (e.g., name, version, maintainer).
- **`overrides`**: Local documentation rules that override the global `config.yaml` for this specific repository.
- **`signature`**: A system-generated checksum or state-hash used to detect drift quickly during `check`.
- **`tree`**: The nested object representing the file system hierarchy.
### 3.1.1 Schema Definition
- The canonical schema should be stored as a JSON Schema document in the repository, for example `Schema/treedocs.schema.json` or `DOCS/treedocs.schema.json`.
- Validation should run against parsed YAML data, not raw YAML text, so `treedocs.yaml` remains YAML while the contract is expressed in JSON Schema.
- The schema should cover root keys, project metadata, override values, signature format, tree entry variants, reserved keys (`_doc`, `_link`), descriptions, and references.
- The schema should be usable outside the Swift CLI by editors, CI, and other agents.
### 3.2 Tree Value Types
To support both simple and deep documentation, a path's value in the `tree` can be:
1. **A String**: For simple, one-line descriptions.
2. **An Object**: For detailed documentation.
    - `description`: (Optional) The primary purpose string.
    - `references`: (Optional) A list of local paths or `https://` URLs for supplementary info.
    - `_doc`: (Reserved for folders) Description for the directory itself.
    - `_link`: (Reserved) Internal or External alias/redirect.
### 3.3 Example Structure
```yaml
project:
  name: "ScraperBot"
  version: "2.1.0"
  last_updated: "2023-10-27"
overrides:
  check_severity: "error"
  icons: true
signature: "sha256:7a8b9c..."
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
        - "[https://wiki.internal.com/db-standards](https://wiki.internal.com/db-standards)"
  docs/architecture:
    _link: "src/api"
    _doc: "Alias to API folder for architectural reference"
  README.md: "Project entry point and installation guide"
```
## 4. Command Definitions
### 4.1 `treedocs init`
Walks the file system and generates a `treedocs.yaml`. It populates the `tree` key, generates an initial `signature`, and initializes `project.name`, `project.version`, and `project.last_updated`.
### 4.2 `treedocs sync`
Reconciles disk state with the `tree` key.
- **Signature Update**: Recalculates and updates the `signature` key after a successful sync.
- `--interactive`: Prompt for descriptions of new files.
### 4.3 `treedocs check`
Non-interactive validation.
1. Compares current disk state against the `signature`.
2. Returns exit code `1` if the `tree` is stale or missing descriptions.
### 4.4 `treedocs inspect`
`treedocs inspect <path> [--recursive]` returns the description, resolves links, and lists all associated `references`.
### 4.5 `treedocs update`
`treedocs update <path> "<description>"` modifies the entry inside the `tree` key and updates the `signature`.

> ❗ The current CLI also supports reference and link mutation flags:
>- `--add-reference`
>- `--remove-reference`
>- `--link`
>- `--clear-link`
### 4.6 `treedocs ls`
Visualizes the `tree` with documentation inline. If a file has `references`, an indicator (like `[+]` or `🔗`) is shown.

> ❗ The current CLI renders subtree output by accepting an optional positional path argument, and its formatter respects `max_description_length`, `indent_size`, and `align_columns`.
## 5. Advanced Features
### 5.1 Alias (`ln`) & External Handling
Supports internal relative links and external URLs via the `_link` key.
### 5.2 Documentation Templates
Defined in `.treedocs/config.yaml` to automatically document files matching specific patterns.
### 5.3 Shell Integration
Search-based navigation: `cd $(treedocs path <query>)`.

> ❗ The current implementation matches against both normalized paths and entry descriptions and returns a single raw path on success.
## 6. What Makes `treedocs` Unique?
### 6.1 Strict Filesystem Mirroring
Maintains a 1:1 structural mirror of the repository, preventing the "map" from drifting from reality.
### 6.2 Collaborative Human-LLM Maintenance
`treedocs init` creates a `treedocs.yaml` that is a recursive tree in YAML form, with empty descriptions. These descriptions can be filled in by an LLM or by a human, making it easy for humans to refine or correct the architectural intent.
### 6.3 Detecting Architectural Drift
Acts as a sentinel that fails when the YAML state no longer matches the filesystem reality, reducing cognitive load for understanding structural shifts.
## 7. Use Cases
1. **Onboarding**: Instant repository overview via `treedocs ls`.
2. **Maintenance**: Quick updates via `treedocs update`.
3. **Governance**: CI enforcement via `treedocs check`.
## 8. Influences & Similar Tools
### 8.1 AI Repository Mappers
- [**RepoMapper**](https://github.com/pdavis68/RepoMapper "null")
- [**Repository Intelligence Graph (RIG)**](https://github.com/Greenfuze/Spade "null")
### 8.2 Enhanced Navigation & Tree Utilities
- [**broot**](https://github.com/Canop/broot "null")
### 8.3 Continuous Documentation
- [**brief**](https://github.com/git-pkgs/brief "null"): A major influence that provides objective truth repo info like toolchains, programming languages used, testing frameworks, CI pipelines, etc.
- [**Swimm**](https://swimm.io/ "null")
- [**DocWeave**](https://dev.to/julsr_mx/cli-tool-that-analyzes-git-repos-and-generates-beautiful-documentation-4e47 "null")
## 9. Future Directions
### 9.1 Model Context Protocol (MCP) Integration
Exposes `inspect` and `ls` as standardized JSON-RPC methods for AI IDEs.
### 9.2 Agent Skill / Toolset
Helps agents identify relevant architectural layers to save tokens in context windows.
