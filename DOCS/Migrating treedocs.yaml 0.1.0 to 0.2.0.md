# Migrating treedocs.yaml 0.1.0 to 0.2.0

Schema `0.2.0` reserves only underscore-prefixed metadata keys inside `tree` entries. This prevents metadata keys from colliding with real filesystem entries named `description/` or `references/`.

## Required Changes

- Change root `schema_version` from `"0.1.0"` to `"0.2.0"`.
- Change object-form `description` metadata to `_description`.
- Change object-form `references` metadata to `_references`.
- Keep compact string descriptions unchanged.
- Keep `_doc` and `_link` unchanged.

Directory documentation stored under `_doc` remains valid. If `_doc` uses object form, rename nested `description` and `references` there too.

## Before

```yaml
schema_version: "0.1.0"
tree:
  Sources:
    _doc:
      description: Source files
      references:
        - DOCS/Sources.md
    main.swift:
      description: Entrypoint
      references:
        - DOCS/Main.md
  README.md: Project overview
```

## After

```yaml
schema_version: "0.2.0"
tree:
  Sources:
    _doc:
      _description: Source files
      _references:
        - DOCS/Sources.md
    main.swift:
      _description: Entrypoint
      _references:
        - DOCS/Main.md
  README.md: Project overview
```

After migration, `_doc`, `_link`, `_description`, and `_references` are reserved metadata names inside `tree`. Non-underscore names are filesystem entries.
