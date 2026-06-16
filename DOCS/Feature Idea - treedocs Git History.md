# Feature Idea - treedocs Git History

`treedocs.yaml` is version controlled with Git, which means treedocs could use Git history as a documentation history store. By reading older versions of `treedocs.yaml`, treedocs could show how file and folder descriptions, references, and links changed over time.

## Feasibility

A first version should be relatively straightforward:

1. Use `git log -- treedocs.yaml` to find commits that changed the documentation file.
2. Use `git show <sha>:treedocs.yaml` to read historical versions.
3. Parse each historical file with the existing config loader.
4. Compare tree entries by documented path.
5. Render changes for a requested file or folder.

The main complexity is path identity over time. Renames, moves, deleted files, nested `treedocs.yaml` boundaries, and delegated subtrees would need careful handling. A useful MVP can ignore some of those cases and improve path tracking later.

## Potential Features

### Documentation History

Show how a file or folder's documentation changed over time.

```bash
treedocs history Sources/treedocs/Core/Scanner.swift
```

This could show previous descriptions, references, links, commit hashes, authors, and dates.

### Documentation Blame

Show when each piece of documentation was last changed.

```bash
treedocs blame Sources/treedocs/Core/Scanner.swift
```

This could answer questions like:

- Who last changed this description?
- When was this reference added?
- Has this `_link` ever changed?

### Stale Documentation Detection

Compare file history against documentation history.

```bash
treedocs stale
```

treedocs could flag files that changed many times after their documentation was last updated.

### Docs Changelog

Generate a changelog of documentation metadata changes.

```bash
treedocs changelog --since v0.4.0
```

This could be useful for releases, documentation reviews, and PR summaries.

### Review Assistance

Warn when files changed in a branch but their treedocs entries did not.

```bash
treedocs check --history
```

This could become a CI-friendly way to catch documentation drift.

### Drift Timeline

Show when documentation likely became stale.

```bash
treedocs drift Sources/treedocs/Core/Scanner.swift
```

The output could list code changes that happened after the last documentation update.

### Historical Tree View

Render the documented tree at a previous commit or tag.

```bash
treedocs ls --at v0.3.0
treedocs inspect Sources/treedocs/Core --at HEAD~20
```

This would make it possible to explore how a project structure evolved over time.

### Documentation Evolution Report

Summarize documentation activity across the project.

```bash
treedocs report history
```

Possible report sections:

- Most frequently updated docs
- Longest unchanged docs
- Recently changed files with unchanged docs
- Deleted entries
- Newly documented paths

### Historical Search

Search current and historical documentation.

```bash
treedocs path "schema validation" --history
```

This could help find renamed, deleted, or moved concepts.

### Documentation Regression Detection

Detect when detailed descriptions are replaced with vague ones.

Example:

```text
Before:
Scans the filesystem while respecting excludes, nested treedocs boundaries, and signature metadata.

After:
Scanner stuff.
```

### Restore Old Documentation

Restore a previous documentation entry without reverting the source file.

```bash
treedocs restore-doc Sources/treedocs/Core/Scanner.swift --from a83f2d1
```

## Promising Commands

```bash
treedocs history <path>
treedocs blame <path>
treedocs stale
treedocs changed --since <ref>
treedocs ls --at <ref>
treedocs restore-doc <path> --from <ref>
```

## Suggested MVP

Start with `treedocs history <path>`.

This command proves the core mechanism:

1. Read historical `treedocs.yaml` versions from Git.
2. Resolve a path into a tree entry.
3. Compare the entry across commits.
4. Render the changes clearly.

After that works, `blame`, `stale`, `changed`, and `restore-doc` become natural follow-up features.
