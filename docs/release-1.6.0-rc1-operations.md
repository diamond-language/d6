# d6 1.6.0-rc1 release verification

The candidate source commit was `f3d4b611`. All 43 checks passed on
[PR #653](https://github.com/diamond-language/d6/pull/653). Its merge
`cf228682` had the same source tree. The tag `v1.6.0-rc1` identifies that
merge. All 39 jobs in [merged-commit CI](https://github.com/diamond-language/d6/actions/runs/45275264231)
passed before the tag was pushed. Bundled cut versions are unchanged since
1.5.0.

All eight [candidate packaging jobs](https://github.com/diamond-language/d6/actions/runs/45271056738)
passed clean installs and standalone builds on x86-64 and arm64. The
unpacked x86-64 tarball passed an isolated mise smoke test. That test
installed a cut with Facet and built a standalone program using type aliases
and typed variadics. All 13 application suites passed against the packaged
interpreter.

## Burn-in

The packaged x86-64 interpreter ran the four-worker Gremlin workload with
20 concurrent clients. The harness reported zero failed requests over 28
batches and 636.5 seconds of load, about 6.13 million requests. The highest
batch p99 was 7 ms. Peak RSS sampled between batches was 3.88 GiB. Mean RSS
across the first and last three batches was 3.60 GiB and 3.65 GiB,
respectively.

The burn-in needed a scratch correction to the Gremlin import after its
source moved into `lib/`. Both benchmark server imports now use that path.
