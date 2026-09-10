---
description: Homebrew formula templates and tap publishing assets for distributing
  treedocs through Homebrew.
readme:
  description: Overview and documentation for contrib/homebrew/.
---

# homebrew

The formula keeps the SwiftPM-built executable and `treedocs_treedocs.bundle` together under Homebrew's private `libexec/` directory, then exposes the command through an executable wrapper in `bin/`. Do not replace the wrapper with a symlink to the executable: on macOS, SwiftPM's generated `Bundle.module` accessor resolves resources relative to the symlink path and will not find the bundle in the Cellar.

After updating the tap formula, run `brew test dandylyons/tap/treedocs`. The test verifies that the resource bundle was installed and runs `treedocs init --non-interactive`, which loads and validates against the bundled schema.
