# Release Strategy

This document defines how `treedocs` releases are cut and how the CLI version relates to the `treedocs.yaml` JSON Schema version.

## CLI Releases

The CLI version is the executable release version reported by `treedocs --version`. It is distinct from `treedocs.yaml` `schema_version` and from the documented project's own `project.version` field.

The first public CLI release will be tagged as `0.1.0` when the project is ready. Do not create the `0.1.0` tag or GitHub Release until the CLI surface, documentation, schema, and package-manager install instructions are ready for external users.

CLI releases should be published through GitHub Releases. The initial release strategy is source-only: users install through SwiftPM-backed tooling that builds locally. Prebuilt binaries, Homebrew bottles, and SwiftPM artifact bundles are deferred until there is a concrete need.

### CLI Version Procedure

1. Update `TreeDocsVersion.current` in `Sources/treedocs/TreeDocs.swift` when the CLI release version changes.
2. Update README and site installation examples when the recommended released version changes.
3. Run `swift build` and `swift test`.
4. Tag the release commit, such as `0.1.0`.
5. Create a GitHub Release for the tag with release notes.
6. Calculate the release source archive SHA256 for Homebrew after GitHub serves the tag archive.
7. Publish or update package-manager distribution entries after the tag exists.

### Package Distribution

Mint and mise can install `treedocs` directly from the tagged GitHub repository and build it from source with Swift Package Manager.

Homebrew distribution should use a dedicated tap repository at `DandyLyons/homebrew-tap`. A single tap can contain formulae for multiple DandyLyons tools. Stable Homebrew formulae should reference the GitHub release source archive and include the archive SHA256, even when the formula builds from source, because Homebrew verifies downloaded source archives before building them.

The formula template in `contrib/homebrew/treedocs.rb` is for preparing the tap formula. After a release tag exists, add a stable `url` and `sha256` to the tap formula before publishing stable Homebrew install instructions. The source archive SHA can be calculated from the release archive URL, for example with `curl -L <archive-url> | shasum -a 256`.

## JSON Schema Releases

The JSON Schema version is the `treedocs.yaml` file-format version stored at root `schema_version`. It is distinct from the CLI release version. A CLI release may support one or more schema versions through bundled schema files and version-aware handling.

Schema versions are canonicalized as public immutable files under `site/schemas/<version>/treedocs.schema.json`. Once a schema version is released, its versioned schema file is not intended to change. If the file format changes, create a new schema version instead of editing an already-released versioned schema.

Generated `treedocs.yaml` files include a managed YAML language-server header that points to the versioned public schema URL. CLI validation remains network-free by loading bundled schema resources.

### Schema Version Procedure

1. Add a new immutable schema directory under `site/schemas/`, such as `site/schemas/0.2.0/`.
2. Set the schema `$id` to the versioned GitHub Pages URL, such as `https://dandylyons.github.io/treedocs/schemas/0.2.0/treedocs.schema.json`.
3. Update `TreedocsSchemaMetadata.currentVersion` and supported schema handling in `Sources/treedocs/Models/TreedocsFile.swift`.
4. Update `Package.swift` so the CLI bundles the new schema file.
5. Update `.env.schema` `CURRENT_TREEDOCS_JSONSCHEMA_VERSION` to the new schema version.
6. Add or update schema validation tests for the new version.
7. Run `swift build` and `swift test`.
8. Merge to `main` to publish the schema through GitHub Pages.

### GitHub Pages Canonization

The `Deploy GitHub Pages` workflow in `.github/workflows/pages.yml` publishes the static files from `site/` whenever `site/**`, `.env.schema`, or the workflow file changes on `main`, and it can also be run manually with `workflow_dispatch`.

During deployment, the workflow loads `.env.schema` with `dmno-dev/varlock-action`. It copies `site/` into a Pages artifact, creates `schemas/latest/`, and copies `site/schemas/$CURRENT_TREEDOCS_JSONSCHEMA_VERSION/treedocs.schema.json` to `schemas/latest/treedocs.schema.json` inside the artifact. The versioned schema URL stays fixed, while the `latest` URL moves forward when `CURRENT_TREEDOCS_JSONSCHEMA_VERSION` changes.

Use versioned schema URLs for generated `treedocs.yaml` headers and stable external references. Use `latest` only for discovery or documentation where moving behavior is acceptable.
