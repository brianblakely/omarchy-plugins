# Okomart Catalog Runtime

Okomart keeps one persistent catalog document at
`$XDG_CACHE_HOME/okomart/catalog.json`. The versioned document contains an
`active` generation and, while a change is waiting, a `pending` generation.
There is no persistent Git mirror, materialized catalog checkout, repository
cache, or duplicate snapshot file.

At storefront startup, Okomart preserves only a valid `catalog.json` in its
cache root and removes every other file, directory, or symlink there. Catalog
locking lives under the state root, while refresh, enrichment, and GitHub tree
scratch data use the private runtime directory and are removed after use.

## Open, Refresh, And Activation

Opening the storefront reads `active` and installed manifests without network
access, then asks the running Omarchy shell for each installed plugin's
authoritative `enabled` and `canDisable` state. A warm launch is therefore
immediately usable. The frontend then starts these independent background
operations:

1. Merge the local `plugins.txt` URLs with compatible standalone HANCORE
   entries and fetch their manifests.
2. Check installed plugin and Okomart remotes for updates, retaining the result
   only in the running storefront.
3. If a changed candidate was staged, resolve required manifest-change
   timestamps only for entries without a HANCORE validation timestamp, then
   mark that exact pending generation ready.

Once a complete active catalog exists, a refresh never changes it directly. A
ready pending generation makes the **オコマート** sign flicker. Pointer
activation or `Enter`/`Space` atomically promotes the generation named by the
sign. Stale enrichment, promotion, and action responses are rejected by
generation.

Enable and disable actions use Omarchy's public plugin commands. Okomart
re-checks the installed path and live enabled state after confirmation before
performing either mutation. A full bar reports `canDisable: false`; Okomart
leaves its Disable button unavailable because bars are replaced by enabling a
different bar rather than switched off directly.

An empty cold cache is the exception. Local URLs are requested first, followed
by compatible HANCORE sources in reverse registry order so its newest listings
arrive first. After every complete request wave, the accumulated validated
manifests atomically replace a partial `active` catalog and a progress event
makes the open storefront reload it. An interrupted cold refresh retains its
last complete wave; a later successful refresh replaces that partial catalog
with the complete generation directly.

Every list-model rebuild anchors the active plugin by id and restores that
row's viewport offset after the replacement. Entries arriving ahead of it do
not move the user's context or send the list back to the top.

The details pane retains its current plugin object and media across those
list-model replacements. A changed active plugin id is the only list-state
transition that refreshes details, so request waves cannot reset details scroll
or media state.

When all manifest waves finish, HANCORE entries are ordered by
`listingValidatedAt`. Timestamp enrichment for sources without that metadata is
staged as the first pending update.

`Ctrl+R` queues a forced refresh when another refresh is in progress. A
registry-source failure leaves `active` untouched. An overall timeout or
all-plugin request failure preserves a complete active catalog; on a cold
refresh, any partial catalog from an earlier completed wave remains available.
When an active catalog is available, Okomart briefly shows the background
refresh failure and then dismisses it after restoring the saved catalog;
without an active catalog, the failure remains visible. Individual plugin
failures are recorded as catalog errors and omitted from the candidate.

## Fetch And Validation Boundaries

GitHub `manifest.json` files come from the raw content endpoint in waves of up
to 16 concurrent requests; GitHub catalog metadata is never cloned. Okomart
uses a compatible HANCORE source's `listingValidatedAt` as its primary ordering
time and its `listingValidatedCommit` as the revision for lazy media. This
metadata also applies when a matching local `plugins.txt` URL wins source
precedence. Okomart does not request a last-update timestamp for those entries.

For sources without validation metadata, path-specific commit feeds provide
the latest commit affecting `manifest.json` through an eight-request enrichment
pool. A new plugin or an entry with no retained timestamp requests one. A
strictly higher SemVer version requests a replacement timestamp; equal versions,
downgrades, and non-SemVer changes retain the previous timestamp. The final
catalog sorts descending by each entry's validation time when present, otherwise
its last-update time, then by case-insensitive name and plugin id.

An arbitrary public HTTPS `.git` host remains supported through a separate
two-worker fallback. Each worker creates a depth-one, blob-filtered,
no-checkout temporary repository, reads the root manifest and HEAD metadata,
then deletes the repository immediately.

Remote catalog validation checks manifest shape, supported kinds, safe
relative entry-point declarations, catalog metadata, ids, and duplicates. It
cannot prove that entry points exist or that the repository tree has no
symlinks because refresh intentionally does not download full trees. Those
authoritative checks remain part of `omarchy plugin add`.

Local `plugins.txt` entries take precedence over HANCORE entries by normalized
repository URL and by validated plugin id. A HANCORE repository that resolves
to an id already supplied by a valid local entry is omitted without recording
an error. Duplicate ids within the same source tier remain catalog validation
errors.

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
