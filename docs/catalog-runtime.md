# Okomart Catalog Runtime

Okomart keeps one persistent catalog document at
`$XDG_CACHE_HOME/okomart/catalog.json`. The versioned document contains an
`active` generation and, while a change is waiting, a `pending` generation.
There is no persistent Git mirror, materialized catalog checkout, repository
cache, or duplicate snapshot file.

## Open, Refresh, And Activation

Opening the storefront reads `active` and installed manifests without network
access, so a warm launch is immediately usable. The frontend then starts these
independent background operations:

1. Merge the local `plugins.txt` URLs with compatible standalone HANCORE
   entries and fetch their manifests.
2. Check installed plugin and Okomart remotes for updates, retaining the result
   only in the running storefront.
3. If a changed candidate was staged, resolve required manifest-change
   timestamps and mark that exact pending generation ready.

The active list never changes merely because a refresh completes. A ready
pending generation makes the **オコマート** sign pulse. Pointer activation or
`Enter`/`Space` atomically promotes the generation named by the sign. Stale
enrichment, promotion, and action responses are rejected by generation.

On a cold cache, successfully fetched manifests are published as `active`
before timestamp enrichment, making the catalog browsable at the first network
boundary. Timestamp enrichment is staged as the first pending update.

`Ctrl+R` queues a forced refresh when another refresh is in progress. A
registry-source failure, overall timeout, or all-plugin request failure leaves
`active` untouched. Individual plugin failures are recorded as catalog errors
and omitted from the candidate.

## Fetch And Validation Boundaries

GitHub `manifest.json` files come from the raw content endpoint through a
16-request HTTP pool; GitHub catalog metadata is never cloned. Path-specific
commit feeds provide the latest commit affecting `manifest.json` through an
eight-request enrichment pool. A new plugin always requests a timestamp. An
existing plugin requests one only when its new version is strictly greater by
SemVer 2.0 precedence. Equal versions, downgrades, and non-SemVer changes retain
the previous timestamp.

An arbitrary public HTTPS `.git` host remains supported through a separate
two-worker fallback. Each worker creates a depth-one, blob-filtered,
no-checkout temporary repository, reads the root manifest and HEAD metadata,
then deletes the repository immediately.

Remote catalog validation checks manifest shape, supported kinds, safe
relative entry-point declarations, catalog metadata, ids, and duplicates. It
cannot prove that entry points exist or that the repository tree has no
symlinks because refresh intentionally does not download full trees. Those
authoritative checks remain part of `omarchy plugin add`.

## Lazy Screenshots

Catalog entries contain no screenshot paths. Details must remain open for 350
ms before discovery starts. Wide-layout selection counts as open details;
narrow layout waits for the details pane. Selection changes, pane closure, and
window closure invalidate the request and discard late responses.

GitHub uses one repository-tree API lookup at the selected revision and emits
revision-pinned raw URLs from supported root, `images/`, and `screenshots/`
locations. Other hosts use at most the current plugin's partial repository in
a private runtime session directory and materialize only matching image blobs.
The directory is removed with the details session, and abandoned sessions are
cleaned on the next launch. Installed screenshots use the same debounce.

Each carousel instantiates only the current image and its wrapping previous and
next neighbors. Images decode asynchronously with QML caching disabled. Tree,
rate-limit, clone, and image failures simply omit screenshots.
