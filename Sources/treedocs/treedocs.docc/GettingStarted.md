# Getting Started With treedocs

Create and maintain a repository map with the `treedocs` command-line interface.

`treedocs` has a sister tool, [`md-utils`](https://github.com/DandyLyons/md-utils), for Markdown parsing, querying, and rewriting. Future integration is planned so repository maps from `treedocs` can work more directly with Markdown operations from `md-utils`.

## Initialize a Repository

Run `init` from a repository root to scan the filesystem and create `treedocs.yaml`:

```bash
treedocs init
```

The generated file contains project metadata, a structural signature, and a recursive `tree` section with empty descriptions ready to fill.

## Fill Descriptions

Use `update` to add descriptions, references, or links for documented entries:

```bash
treedocs update Sources/treedocs/Core "Core scanning, rendering, and config logic"
treedocs update README.md --add-reference DOCS/schema-cli-usage.md
treedocs update Sources/treedocs/Commands --link Sources/treedocs/TreeDocs.swift
```

Descriptions are stored inline in `treedocs.yaml`. References and `_link` targets use mapping entries when a path needs more metadata than plain text.

## Keep State Current

After the filesystem changes, run `sync` to reconcile `treedocs.yaml` with the current repository layout while preserving compatible descriptions, references, and links:

```bash
treedocs sync
```

When stdin and stdout are attached to a TTY, `sync` opens an interactive flow for filling missing descriptions before saving. Use `-n, --non-interactive` to skip terminal UI explicitly:

```bash
treedocs sync --non-interactive
treedocs sync -n
```

Non-TTY contexts skip interactive UI automatically.

Use `check` in local workflows or CI to detect stale signatures and missing descriptions:

```bash
treedocs check
```

## Read the Map

Render the whole tree or a subtree with `ls`:

```bash
treedocs ls
treedocs ls Sources/treedocs
```

Inspect one entry when you need references, link resolution, or recursive child output:

```bash
treedocs inspect Sources/treedocs --recursive
```

Find a documented path from a query with `path`:

```bash
treedocs path renderer
```

## Configuration

Configuration is resolved from defaults, optional global config, optional project config, and `treedocs.yaml` overrides. Important options include ignore patterns, `.gitignore` loading, render formatting, and check severity.

Project-level configuration lives at `.treedocs/config.yaml`, and additional project ignore rules live at `.treedocs/.treedocs_ignore`.
