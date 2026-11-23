# d6 1.5.0 publication record

Published on 2026-11-23 UTC.

`v1.5.0` identifies `046e79b4`, the merge of
[PR #645](https://github.com/diamond-language/d6/pull/645). All 43 PR checks and
all 39 jobs in the [merged-commit CI run](https://github.com/diamond-language/d6/actions/runs/45089808103)
passed. Local tests passed, and the documentation build checked 14,501 links
without a broken link. Quarry passed all 14 CLI tests and 1,035 jq comparisons
on the optimized runtime. Its standalone build passed JSON stream and lazy
generator smoke tests.

The [release workflow](https://github.com/diamond-language/d6/actions/runs/45091422168)
built, installed, and smoke-tested all eight packages, built the VS Code
extension, and published the assets for
[d6 1.5.0](https://github.com/diamond-language/d6/releases/tag/v1.5.0).

HTTP 0.2.9 was published from the reviewed inventory after verifying a registry
snapshot. All 19 HTTP package tests passed on d6 1.4.0, its minimum supported
version. The release archive digest matched the inventory, the scoped
credential was revoked, and public verification resolved, digest-checked,
loaded, and reinstalled all 27 cuts from an unchanged lockfile. See the
[registry production record](../applications/registry/deploy/PRODUCTION.md).
