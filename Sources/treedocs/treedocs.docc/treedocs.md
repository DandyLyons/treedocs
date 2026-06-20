# ``treedocs``

Keep a version-controlled architectural map of a repository in `treedocs.yaml`.

## Overview

`treedocs` is a Swift command-line tool that scans a repository, records its visible filesystem structure, and stores descriptions, references, and links in a YAML state file. It helps teams detect documentation drift, keep path-level context close to the source tree, and query documented paths from shell workflows.

[`md-utils`](https://github.com/DandyLyons/md-utils) is a sister tool maintained and designed by the same author. It focuses on Markdown parsing, querying, and rewriting through a Swift library, CLI, and Agent Skill, while `treedocs` focuses on repository structure and path-level documentation. Planned integration will connect these complementary workflows.

The CLI centers on a few repository workflows:

- Initialize `treedocs.yaml` from the current filesystem.
- Sync stored documentation after files or directories change.
- Check whether the stored tree is stale or has missing descriptions.
- Render, inspect, update, and search documented paths.

## Topics

### Getting Started

- <doc:GettingStarted>
