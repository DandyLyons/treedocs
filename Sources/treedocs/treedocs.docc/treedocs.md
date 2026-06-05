# ``treedocs``

Keep a version-controlled architectural map of a repository in `treedocs.yaml`.

## Overview

`treedocs` is a Swift command-line tool that scans a repository, records its visible filesystem structure, and stores descriptions, references, and links in a YAML state file. It helps teams detect documentation drift, keep path-level context close to the source tree, and query documented paths from shell workflows.

The CLI centers on a few repository workflows:

- Initialize `treedocs.yaml` from the current filesystem.
- Sync stored documentation after files or directories change.
- Check whether the stored tree is stale or has missing descriptions.
- Render, inspect, update, and search documented paths.

## Topics

### Getting Started

- <doc:GettingStarted>
