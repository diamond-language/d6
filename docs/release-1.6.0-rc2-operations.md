# d6 1.6.0-rc2 publication and deployment record

Published 2026-11-24 UTC as a prerelease at `62d13ad7`, the merge of
[PR #658](https://github.com/diamond-language/d6/pull/658). All 43 PR checks
and all 39 [merged-commit CI jobs](https://github.com/diamond-language/d6/actions/runs/45325870637)
passed. The merged tree matched candidate commit `8dcd04c3`.

All eight [candidate packaging jobs](https://github.com/diamond-language/d6/actions/runs/45322810708)
passed on x86-64 and arm64. The [release workflow](https://github.com/diamond-language/d6/actions/runs/45328115298)
published nine assets. The package checksums matched GitHub's digests, and
a fresh mise install built and ran a standalone program.
[Release](https://github.com/diamond-language/d6/releases/tag/v1.6.0-rc2)

The packaged x86-64 interpreter ran the four-worker Gremlin burn-in with
JIT enabled and 20 concurrent clients. The harness reported zero failed
requests over 28 batches, 625.2 seconds, and about 6.20 million requests.
The highest batch p99 was 6 ms. Peak RSS sampled between batches was
3.66 GiB. All 14 application suites passed on the packaged runtime.

## Production

All three running executables matched their verified build checksums and
had JIT enabled. The release reused the existing published cut versions.

| Service | Build and verification | Rollback |
| --- | --- | --- |
| Registry | `tools/deploy_registry.sh` with the RC2 tag. Health and all 27 public cut checks passed. | Verified off-host snapshot in the [registry production record](../applications/registry/deploy/PRODUCTION.md). |
| Pheint | App `e2489735`, built on the Ubuntu deployment VM. The deploy script's eight external checks passed. [Pin PR](https://github.com/diamond-language/pheint/pull/60) | Data backup `/var/backups/pheint/20261124T045244Z/` and previous deployment files in `/root/pheint-1.6.0-rc2-rollback.hedUYb`. |
| Skindicate | App `90bed2c0`, from the [merged-commit bundle](https://github.com/diamond-language/skindicate-v3/actions/runs/45327236926). Homepage, browse, Unicode search, login, skin, profile, and download checks passed. | Database snapshot `/var/backups/skindicate-v3/skindicate-20261124T045258Z.db.gz` and previous deployment files in `/root/skindicate-1.6.0-rc2-rollback.eiTk5z`. |
