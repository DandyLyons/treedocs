# treedocs Schema CLI Usage

This note summarizes which parts of `DOCS/treedocs.schema.json` are currently used by the CLI and which parts are parsed or preserved but not yet meaningfully exposed.

## Actively Used

The CLI currently takes advantage of these schema fields:

- `project.name`: written by `treedocs init`.
- `signature`: written by `init`, `sync`, and `update`; checked by `check` and `show` drift warnings.
- `tree`: core documentation state used by all tree-oriented commands.
- `description`: rendered by `show`/`ls`, searched by `path`, updated by `update`, checked for missing documentation by `check` and interactive `sync`.
- `_doc`: directory documentation parsed, rendered, preserved, and updated through the tree model.
- `_link`: set and cleared by `update`, resolved by `show` and `inspect`, and surfaced in tree output.
- `references`: set and removed by `update`, shown by `inspect`, preserved by `sync`, and marked in tree output with `[ref]`.
- `overrides.exclude`: contributes scanner ignore patterns.
- `overrides.use_gitignore`: controls whether `.gitignore` contributes scanner ignore patterns.
- `overrides.max_description_length`: controls rendered description truncation.
- `overrides.align_columns`: controls rendered tree column alignment.
- `overrides.check_severity`: controls whether `check` issues fail or warn, and affects missing-description coloring.

## Partially Used

These schema features are supported, but only lightly:

- `_link`: link resolution exists, but the schema only requires a non-empty string. Most link semantics are enforced by CLI behavior rather than schema validation.
- Slash-separated tree keys: the loader accepts keys like `Sources/foo.swift`, but the writer normalizes state back into nested YAML. This is useful input compatibility, not a distinct CLI feature.
- `references`: references are editable and displayable, but the CLI does not resolve, open, check existence, or search reference targets beyond schema validation.

## Not Currently Used

The schema and model support these fields, but the CLI does not currently take advantage of them:

- `overrides.indent_size`: parsed and has a default, but rendering still uses hard-coded tree prefixes, so the value has no visible effect.
- `overrides.auto_init_empty`: parsed, merged, serialized, and exposed as `resolvedAutoInitEmpty`, but no command uses it.
- `overrides.theme`: parsed and preserved, but no renderer/theme behavior uses it.
- `overrides.icons`: parsed and preserved, but tree output does not render icons.
- `overrides.ai_provider`: parsed and preserved, but prompt/AI workflows do not use it.
- `overrides.ai_model`: parsed and preserved, but prompt/AI workflows do not use it.
- Extra `project` metadata keys: schema allows arbitrary string-valued project metadata and the model preserves it, but no CLI command displays or edits it.
- `project.version`: created as `0.0.0` during `init` and preserved afterward, but not otherwise used by CLI behavior.
- `project.last_updated`: set during `init`, but `sync` and `update` do not currently refresh it.

## Validation Note

`TreedocsFileStore.save` validates the written `treedocs.yaml` against the canonical schema after saving. This prevents CLI mutations from silently producing schema-invalid state, such as invalid reference formats.
