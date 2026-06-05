# Getting Started With treedocs

Create and maintain a repository map with the `treedocs` command-line interface.

## Initialize a Repository

Run `init` from a repository root to scan the filesystem and create `treedocs.yaml`:

```bash
swift run treedocs init
```

The generated file contains project metadata, a structural signature, and a recursive `tree` section with empty descriptions ready to fill.

## Fill Descriptions

Use `update` to add descriptions, references, or links for documented entries:

```bash
swift run treedocs update Sources/treedocs/Core "Core scanning, rendering, and config logic"
swift run treedocs update README.md --add-reference DOCS/InitialSpecs.md
swift run treedocs update Sources/treedocs/Commands --link Sources/treedocs/TreeDocs.swift
```

Descriptions are stored inline in `treedocs.yaml`. References and `_link` targets use mapping entries when a path needs more metadata than plain text.

## Keep State Current

After the filesystem changes, run `sync` to reconcile `treedocs.yaml` with the current repository layout while preserving compatible descriptions, references, and links:

```bash
swift run treedocs sync
```

Use `check` in local workflows or CI to detect stale signatures and missing descriptions:

```bash
swift run treedocs check
```

## Read the Map

Render the whole tree or a subtree with `ls`:

```bash
swift run treedocs ls
swift run treedocs ls Sources/treedocs
```

Inspect one entry when you need references, link resolution, or recursive child output:

```bash
swift run treedocs inspect Sources/treedocs --recursive
```

Find a documented path from a query with `path`:

```bash
swift run treedocs path renderer
```

## Configuration

Configuration is resolved from defaults, optional global config, optional project config, and `treedocs.yaml` overrides. Important options include ignore patterns, `.gitignore` loading, render formatting, and check severity.

Project-level configuration lives at `.treedocs/config.yaml`, and additional project ignore rules live at `.treedocs/.treedocs_ignore`.
