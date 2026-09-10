---
name: releasing-treedocs
description: Prepare, modify, validate, or publish treedocs releases. Use before any release-related change, including CLI or schema versions, release documentation, tags, GitHub Releases, GitHub Pages publication, checksums, Homebrew formulae or tap updates, Mint or mise instructions, and release automation.
---

# Releasing treedocs

Before making or preparing any release-related change:

1. Read `DOCS/Release Strategy.md` completely from the repository root.
2. Treat that document as the authoritative release procedure and follow the applicable steps in their documented order.
3. Identify every affected release surface: CLI, JSON Schema, GitHub Pages, and package distribution.
4. Keep the CLI version, JSON Schema version, and documented project version distinct unless the release strategy explicitly requires them to change together.
5. For package-distribution work, verify the authoritative repository, checkout, formula, tag, archive URL, and published state before editing or testing. Do not assume a similarly named local checkout is the one used by Homebrew or another package manager.
6. Run the verification commands required by the release strategy for the affected release surface.

Do not create or push tags, publish GitHub Releases or Pages, update a remote tap, or otherwise change external release state without the user's authorization.

If `DOCS/Release Strategy.md` is missing, unreadable, ambiguous, or inconsistent with the repository's current release machinery, pause release-related changes and report the problem before proceeding.
