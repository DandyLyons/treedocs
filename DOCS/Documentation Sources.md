# Documentation sources in 0.3.0-WIP

The opt-in state schema `0.3.0-WIP` extends `0.2.0` with `overrides.documentation_sources`. Published `0.1.0` and `0.2.0` schemas are unchanged and reject this property. Set `schema_version` to `0.3.0-WIP` before adding the mapping; sync refreshes the managed schema header. The staging schema is bundled for offline validation. New repositories and the public `latest` endpoint continue to use stable `0.2.0` while staging remains opt-in.

```yaml
schema_version: 0.3.0-WIP
overrides:
  documentation_sources:
    .github/: FOLDER.md
    .: PROJECT.md
```

Keys are exact repository-relative directory paths with trailing slashes, or `.` for the root. Empty components, absolute paths, backslashes, and dot traversal components are rejected. Values are nonblank filenames without directory components; `.` and `..` are invalid. There is no configurable default and no inheritance. Every unconfigured folder uses `README.md`.

Discovery, sync, check, population, and stub creation use the same selector. Selecting `.github/FOLDER.md` leaves `.github/README.md` visible as an ordinary file, whose frontmatter supplies no documentation. Descendant folders independently select their own sources. Exclusions and nested state ownership boundaries continue to apply. Overrides within delegated nested roots do not cause parent scans to inspect their files.

An explicit missing source, excluded source, or missing/excluded source folder produces a diagnostic with a configuration or creation remedy. Missing implicit READMEs are fine. A selected file must be a file with the exact configured spelling. Changing configuration never renames, deletes, or converts either file.

Use `treedocs createDoc .github/` to create the selected source from canonical folder metadata; existing files are skipped. `treedocs sync --populate-docs children` or `treedocs sync --populate-docs recursive` copies missing descriptions into recognized source frontmatter. Plain Markdown files stay plain. The legacy `createREADME` command and `--populate-readmes` option are aliases with identical selection behavior.

## Markdown frontmatter contract

This contract is separate from the JSON Schema for `treedocs.yaml`. Source frontmatter continues to use unprefixed `description` and `references`, while the state tree uses `_description` and `_references`.

```yaml
---
description: Automation configuration.
file:
  description: Folder documentation for automation.
  references: [../DOCS/Architecture.md]
tree:
  workflows/:
    _doc: Workflow definitions.
---
# Automation
```

Top-level fields describe the containing folder. `file:` describes the selected Markdown file itself. Sparse `tree:` metadata describes owned descendants. Relative references resolve against the containing folder. Intentional blank descriptions (`_`), conflict resolution, descendant population, and Markdown body preservation retain their existing behavior. Root-folder metadata remains deferred; root sources may document their file and descendants.

Legacy `readme:` remains supported regardless of filename or state version. If both `file:` and `readme:` exist, each must be a mapping and their supported fields must agree after normalization. References compare as sets; an omitted references field differs from an explicit empty list. Disagreement fails before writes with a diagnostic asking the user to combine metadata under `file:`. Unsupported keys remain preserved. Accepted dual mappings are both updated when a conflict is resolved. Legacy-only sources keep their spelling; newly generated stubs use `file:`.
