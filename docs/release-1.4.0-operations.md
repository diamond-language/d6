# 1.4.0 publication and deployment record

Completed 2026-11-22 UTC.

`v1.4.0` identifies `189b9974`, the merge of
[PR #637](https://github.com/diamond-language/d6/pull/637). Its head passed all 43 checks and
had the same tree as the merge commit. Before the PR, `make test` passed locally, and a 5-minute,
4-worker compile-fuzz run seeded with the parser cases found only a stack overflow under ASan
on about 1,800 nested `[`. Release builds of both 1.3.1 and 1.4.0 reject that input with an
ordinary parse error, so the overflow is not new and does not affect release builds.

1.4.0 is the first minor release with a breaking change, under the rewritten
[compatibility policy](compatibility.md): Strings count characters. See the
[release notes](release-1.4.0.md).

## Published assets

The release workflow built, installed and smoke-tested all eight packages before publishing.
GitHub marks [d6 1.4.0](https://github.com/diamond-language/d6/releases/tag/v1.4.0) Latest
(release run 45002284959).

| Asset | SHA-256 |
|---|---|
| `d6-1.4.0-linux-aarch64.tar.gz` | `08a2a3278c2bebdc7726ce3ec0d2d3bb53375901382fb8793cafb84de97ebc04` |
| `d6-1.4.0-linux-x86_64.tar.gz` | `df19e208e33e0905063ed4863279ebf2eae73352cca8f941d1c82494035a193e` |
| `d6-lang-1.4.0-1.fc44.aarch64.rpm` | `2045fdea0bf452f1f591f7269dc4fa6cdf8cd21ac15d771280afafb60c997bcf` |
| `d6-lang-1.4.0-1.fc44.x86_64.rpm` | `67e61465a03f9ba9e9755e6a822d742cc48c34619347546cd0cabce557377969` |
| `d6-lang-1.4.0-1.fc45.aarch64.rpm` | `ed7087a8fb777b5b24911d75a4fba344a0f126bfe355ae2e74258a0afdef4622` |
| `d6-lang-1.4.0-1.fc45.x86_64.rpm` | `3388111e78b136a278b1cf8b8256a2c0b1f793f6d6d6a6c9d51bc2d96a51ee35` |
| `d6-lang_1.4.0-1_amd64.deb` | `a34870cf99703688483eee8bb3e578ff38b25bf32ec06787ed3fbe63ce9a2fa0` |
| `d6-lang_1.4.0-1_arm64.deb` | `89fc144b62b2212e483177ae583cca48c8d89c817a2450a119c91237ad79b827` |
| `d6-vscode.vsix` | `b31246972191fe3dad628c4136bf2ec5aeb65bc85d03a97b47167f3bc6daef36` |

## Registry and cuts

The registry went first. Ten of the new cut releases say `"d6": ">=1.4.0"` in their Cutfile,
and a registry that doesn't know that field would serve them to older d6 releases.
`tools/deploy_registry.sh --no-verify --revision=v1.4.0` ran after its dry run. The upgrade check
reported REQUIRED (38 runtime files had changed). The verified snapshot is
`~/diamond-registry-backups/cutbackup-2026-11-22-002138-pre-189b9974`.

Then 12 cuts were published from the tag: cookies 0.2.7, csv 0.1.1, div 0.3.4, gremlin 0.5.8,
html 0.1.1, http 0.2.8, redis 0.2.5, registry 0.3.3, toml 0.1.2 and websocket 0.2.5 (fixed for
character Strings), plus graphql 0.3.7 and the new terminal 0.1.0. The seed was trimmed to those
12 with `tools/trim_seed_to.d6`, and one 30-minute credential was scoped to them (id 51, revoked
afterwards). Every published sha256 matches `docs/registry-launch-inventory.json`, and
`tools/verify_registry_launch.d6` passed for all 26 public cuts. A query with `?d6=1.3.1`
resolves http to 0.2.7, and one with `?d6=1.4.0` resolves it to 0.2.8.

The publisher itself needed a fix first
([PR #638](https://github.com/diamond-language/d6/pull/638)). It compared archive sizes and sent
Content-Length with `length()`, which counts characters from 1.4.0. The cuts were published with
the fixed tool.

## Site and docs

| Target | Deployed source | Verification |
|---|---|---|
| Marketing | Marketing `1c80d41` (green PR #54) | Fresh WASM from `v1.4.0` (`67d504bd93f0217748eaa90aba229d7531d16418ce7d22a3ecf62b1e0eef2f7a`), `make test-wasm` and the site REPL tests; live: 1.4.0 eyebrow, all six download links return 200, WASM digest with `application/wasm` and `no-cache` |
| Docs | `v1.4.0` | 101 pages, 14,040 links checked, none broken; new pages for the 1.4.0 release notes and the markdown, mustache and terminal cuts |

`RELEASE`, `REVISION` and `RUNTIME_REVISION` in the document root say 1.4.0, `1c80d41` and
`189b9974`. The document root from before 1.4.0 is in
`/root/d6-1.4.0-rollback-20261122/site.tar.gz`. nginx and TLS were not touched.

## Production applications

Both applications used `length()` as a byte count, which counts characters from 1.4.0, and
were fixed before moving.

| Target | Deployed source | Verification | Rollback |
|---|---|---|---|
| SkindicateV3 | App `c467e1e` (skindicate-v3 #32: `url_encode` walks UTF-8 bytes, so `é` is `%C3%A9`, not `%E9`; runtime pin to `v1.4.0`), main CI run 45003906403 bundle | Running binary SHA-256 `1a12b94f...` matched the bundle; `DIAMOND_JIT=1` kept; homepage, browse (including a non-ASCII search), login, skin, download and profile pages; no errors or 5xx logged (45 MB) | `/root/skindicate-1.4.0-rollback` |
| Pheint | App `2c6026f` (pheint #58: save and replay sizes, upload limits, the GraphQL body limit and bcrypt's 72-byte cap use `bytesize`; registry cuts updated with `facet update`; runtime pin to `v1.4.0`), built on the local VM | `build_vm.sh` source suite, prebuilt suite with and without the JIT, standalone smoke; running binary SHA-256 `9f8d0235...` matched the build; the deploy script's eight outside checks passed (55 MB); an anonymous `me` query got `UNAUTHENTICATED` | `/var/backups/pheint/20261122T085905Z` |

`main` then moved to 1.5.0-dev ([#639](https://github.com/diamond-language/d6/pull/639)).
