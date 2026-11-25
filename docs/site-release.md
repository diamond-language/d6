# Publish the website for a stable d6 release

Update the package examples and version output in [Getting Started](getting-started.md)
before tagging. Add the release notes to [the docs index](docsite.txt) when the
release has a new notes page. A stable tag's GitHub release workflow builds
the curated docs using the packaged Linux runtime, checks the examples and
links, and builds and tests the browser runtime from the tag. The GitHub
release waits for the resulting `site-vX.Y.Z` artifact. Release candidates
continue to use the stable public site.

After GitHub publishes the release, download its site artifact from the
successful release run:

```sh
tag=vX.Y.Z
gh run download RUN_ID --repo diamond-language/d6 --name "site-$tag" --dir build
```

In [the marketing repository](https://github.com/diamond-language/marketing),
update the homepage version and all six package URLs. Copy the artifact's
`diamond.wasm` into `wasm/` and `diamond-wasm.js` into `js/`. Run
`node --test tests/repl.test.mjs` there and land the marketing PR through CI.

From the d6 checkout, with the stable tag fetched and the marketing checkout
updated to its merged main, publish with the existing site operator SSH access:

```sh
bash packaging/publish_site_release.sh deploy "build/site-release-${tag#v}" ../marketing
```

The command verifies the artifact checksums and release revisions, runs the
marketing REPL tests, previews the sync, and atomically switches to the staged
site. It checks the live homepage and Getting Started version, all six downloads,
and the live browser loader and WebAssembly bytes. A failed smoke test restores
the previous site. On success, record the printed backup location with the
deployment in the marketing repository. The same live checks can be rerun
without changing the site:

```sh
bash packaging/publish_site_release.sh verify "build/site-release-${tag#v}"
```
