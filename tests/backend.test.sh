#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OKOMART="$ROOT/bin/okomart"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_CACHE_HOME="$TMP/cache"
export XDG_CONFIG_HOME="$TMP/config"
export XDG_STATE_HOME="$TMP/state"
export OKOMART_PLUGINS_DIR="$TMP/installed"
export OKOMART_GIT_TIMEOUT_SECONDS=3
export OKOMART_TEST_ALLOW_LOCAL_REGISTRY_URLS=1
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
export GIT_TERMINAL_PROMPT=0
mkdir -p "$HOME" "$OKOMART_PLUGINS_DIR" "$TMP/bin"

git config --global user.name "Okomart Tests"
git config --global user.email "okomart@example.invalid"
git config --global init.defaultBranch main
git config --global protocol.file.allow always

pass_count=0
fail() {
  printf 'not ok %d - %s\n' "$((pass_count + 1))" "$*" >&2
  exit 1
}

pass() {
  pass_count=$((pass_count + 1))
  printf 'ok %d - %s\n' "$pass_count" "$1"
}

assert_jq() {
  local file="$1"
  local expression="$2"
  local message="$3"
  jq -e "$expression" "$file" >/dev/null || fail "$message"
  pass "$message"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [[ $actual == "$expected" ]] || {
    printf 'expected: %s\nactual:   %s\n' "$expected" "$actual" >&2
    fail "$message"
  }
  pass "$message"
}

assert_stale_cache_integrity() {
  local snapshot="$1"
  local expected_image_path="$2"
  local expected_image_sha="$3"
  local label="$4"
  local snapshot_commit cache_commit image_path image_sha
  local plugin_commit plugin_path plugin_dir plugin_cache_commit
  snapshot_commit="$(jq -r '.catalogCommit' "$snapshot")"
  cache_commit="$(
    jq -r '.catalogCommit' \
      "$XDG_CACHE_HOME/okomart/catalog/.okomart-index.json"
  )"
  assert_eq "$snapshot_commit" "$cache_commit" \
    "$label keeps the materialized catalog aligned with stale JSON"
  image_path="$(
    jq -r '[.plugins[]|select(.id=="b.alpha")][0].images[0]' "$snapshot"
  )"
  assert_eq "$expected_image_path" "$image_path" \
    "$label preserves the prior screenshot path"
  [[ -f $image_path ]] || fail "$label removed the prior screenshot"
  pass "$label preserves the prior screenshot file"
  plugin_commit="$(
    jq -r '[.plugins[]|select(.id=="b.alpha")][0].catalogCommit' "$snapshot"
  )"
  plugin_path="$(
    jq -r '[.plugins[]|select(.id=="b.alpha")][0].catalogPath' "$snapshot"
  )"
  plugin_dir="$XDG_CACHE_HOME/okomart/catalog/$plugin_path"
  plugin_cache_commit="$(
    jq -r '[.entries[]|select(.id=="b.alpha")][0].catalogCommit' \
      "$XDG_CACHE_HOME/okomart/catalog/.okomart-index.json"
  )"
  assert_eq "$plugin_commit" "$plugin_cache_commit" \
    "$label keeps the materialized plugin aligned with stale JSON"
  [[ ! -e $XDG_CACHE_HOME/okomart/catalog/.git &&
    ! -e $plugin_dir/.git ]] ||
    fail "$label duplicated Git history into a display checkout"
  pass "$label display trees contain no duplicated Git object databases"
  image_sha="$(sha256sum "$image_path" | awk '{print $1}')"
  assert_eq "$expected_image_sha" "$image_sha" \
    "$label preserves the prior screenshot bytes"
}

REAL_TIMEOUT_BIN="$(command -v timeout)"
REAL_TAR_BIN="$(command -v tar)"
TIMEOUT_LOG="$TMP/timeout.log"
export REAL_TIMEOUT_BIN REAL_TAR_BIN TIMEOUT_LOG
cat >"$TMP/bin/timeout" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TIMEOUT_LOG"
if [[ ${MOCK_TIMEOUT_PLUGIN_FETCH:-} == 1
    && " $* " == *"/.mirror.tmp.plugin."*".git fetch "* ]]; then
  exit 124
fi
exec "$REAL_TIMEOUT_BIN" "$@"
MOCK
cat >"$TMP/bin/tar" <<'MOCK'
#!/usr/bin/env bash
if [[ ${MOCK_TAR_FAILURE:-} == 1 ]]; then
  exit 9
fi
exec "$REAL_TAR_BIN" "$@"
MOCK
chmod +x "$TMP/bin/timeout" "$TMP/bin/tar"
export PATH="$TMP/bin:$PATH"

HYPRCTL_LOG="$TMP/hyprctl.log"
export HYPRCTL_LOG
cat >"$TMP/bin/hyprctl" <<'MOCK'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"$HYPRCTL_LOG"

if [[ ${1:-} == eval && ${2:-} == hl.window_rule* ]]; then
  if [[ ${MOCK_HYPR_FAIL:-0} == 1 ]]; then
    printf 'Lua evaluation failed\n' >&2
    exit 0
  fi
  printf 'ok\n'
  exit 0
fi

exit 1
MOCK
chmod +x "$TMP/bin/hyprctl"

reset_hypr_fixture() {
  : >"$HYPRCTL_LOG"
}

reset_hypr_fixture
"$OKOMART" prepare-window 760 >"$TMP/window-preparation.json"
assert_jq "$TMP/window-preparation.json" \
  '.ok and .prepared and .width==760 and .height==760' \
  "target Lua rule is registered before Okomart maps"
grep -Fq 'eval hl.window_rule({ name = "okomart-floating-window"' \
  "$HYPRCTL_LOG" ||
  fail "window preparation did not register a named Lua rule"
grep -Fq 'match = { class = "^org.quickshell$", title = "^Okomart$" }' \
  "$HYPRCTL_LOG" ||
  fail "window preparation rule is not scoped to Okomart"
grep -Fq 'float = true, center = true, size = { 760, 760 }' \
  "$HYPRCTL_LOG" ||
  fail "window preparation rule does not request floating square geometry"
if grep -Eq \
  'hl\.dsp\.window|setfloating|togglefloating|resizewindowpixel|movewindowpixel|centerwindow' \
  "$OKOMART"; then
  fail "window preparation still contains a post-map or legacy dispatcher"
fi
pass "window preparation supports only the target Lua rule API"

reset_hypr_fixture
if MOCK_HYPR_FAIL=1 "$OKOMART" prepare-window 760 \
  >"$TMP/window-preparation-failed.json"; then
  fail "Lua evaluation errors should fail window preparation"
fi
assert_jq "$TMP/window-preparation-failed.json" \
  '(.ok|not) and .error=="Could not register the Okomart window rule"' \
  "target Lua rule errors are rejected"

write_plugin_manifest() {
  local target="$1"
  local id="$2"
  local name="$3"
  local version="$4"
  jq -n \
    --arg id "$id" \
    --arg name "$name" \
    --arg version "$version" \
    '{
      schemaVersion:1,id:$id,name:$name,version:$version,
      author:"Test Author",description:($name + " description"),
      license:"MIT",kinds:["panel"],entryPoints:{panel:"Panel.qml"}
    }' >"$target/manifest.json"
}

make_plugin_repo() {
  local slug="$1"
  local id="$2"
  local name="$3"
  local version="$4"
  local work="$TMP/$slug-work"
  local remote="$TMP/$slug.git"
  mkdir -p "$work"
  git -C "$work" init -q
  write_plugin_manifest "$work" "$id" "$name" "$version"
  printf 'import QtQuick\nItem {}\n' >"$work/Panel.qml"
  git -C "$work" add .
  git -C "$work" commit -qm "$slug $version"
  git clone -q --bare "$work" "$remote"
  git -C "$work" remote add origin "$remote"
  git -C "$work" push -q -u origin main
}

advance_plugin() {
  local slug="$1"
  local version="$2"
  local work="$TMP/$slug-work"
  jq --arg version "$version" '.version=$version' "$work/manifest.json" \
    >"$work/manifest.json.next"
  mv "$work/manifest.json.next" "$work/manifest.json"
  printf '// %s\n' "$version" >>"$work/Panel.qml"
  git -C "$work" add .
  git -C "$work" commit -qm "$slug $version"
  git -C "$work" push -q origin main
}

advance_plugin_without_version() {
  local slug="$1"
  local work="$TMP/$slug-work"
  printf '// same manifest version\n' >>"$work/Panel.qml"
  git -C "$work" add Panel.qml
  git -C "$work" commit -qm "$slug code-only change"
  git -C "$work" push -q origin main
}

make_plugin_repo alpha b.alpha Alpha 1.0.0
# Give the fixture enough reachable history to catch an accidental unshallow
# mirror fetch without making the checked-out HEAD tree itself large.
for history_revision in $(seq 1 80); do
  printf 'history revision %03d\n' "$history_revision" \
    >"$TMP/alpha-work/.deep-history-fixture"
  git -C "$TMP/alpha-work" add .deep-history-fixture
  git -C "$TMP/alpha-work" commit -qm \
    "alpha deep history fixture $history_revision"
done
mkdir -p "$TMP/alpha-work/images" "$TMP/alpha-work/screenshots/nested"
printf 'jpg' >"$TMP/alpha-work/shot1.jpg"
printf 'png' >"$TMP/alpha-work/images/shot10.png"
printf 'png' >"$TMP/alpha-work/screenshots/shot2.PNG"
printf 'ignored' >"$TMP/alpha-work/images/readme.txt"
printf 'ignored' >"$TMP/alpha-work/screenshots/nested/shot0.png"
printf 'ignored' >"$TMP/alpha-work/root-image.svg"
git -C "$TMP/alpha-work" add shot1.jpg images screenshots root-image.svg
git -C "$TMP/alpha-work" commit -qm "alpha screenshots"
git -C "$TMP/alpha-work" push -q origin main
ALPHA_V1="$(git -C "$TMP/alpha-work" rev-parse HEAD)"
ALPHA_V1_UPDATED_AT="$(git -C "$TMP/alpha-work" show -s --format=%ct "$ALPHA_V1")"
ALPHA_REMOTE_HISTORY_COUNT="$(
  git -C "$TMP/alpha.git" rev-list --all --count
)"
(( ALPHA_REMOTE_HISTORY_COUNT >= 82 )) ||
  fail "deep-history plugin fixture was not prepared"

make_plugin_repo beta b.beta Beta 1.0.0
mkdir -p "$TMP/beta-work/images"
printf 'webp' >"$TMP/beta-work/images/only.webp"
git -C "$TMP/beta-work" add images
git -C "$TMP/beta-work" commit -qm "beta screenshot"
git -C "$TMP/beta-work" push -q origin main
BETA_V1="$(git -C "$TMP/beta-work" rev-parse HEAD)"
make_plugin_repo gamma b.gamma Gamma 1.0.0
make_plugin_repo dirty b.dirty Dirty 1.0.0
make_plugin_repo ahead b.ahead Ahead 1.0.0
make_plugin_repo split b.split Split 1.0.0
make_plugin_repo linked b.linked Linked 1.0.0
make_plugin_repo samever b.samever SameVersion 1.0.0

mkdir -p "$TMP/invalid-work"
git -C "$TMP/invalid-work" init -q
write_plugin_manifest "$TMP/invalid-work" b.undocumented Undocumented 1.0.0
jq 'del(.author)' "$TMP/invalid-work/manifest.json" \
  >"$TMP/invalid-work/manifest.json.next"
mv "$TMP/invalid-work/manifest.json.next" "$TMP/invalid-work/manifest.json"
printf 'import QtQuick\nItem {}\n' >"$TMP/invalid-work/Panel.qml"
git -C "$TMP/invalid-work" add .
git -C "$TMP/invalid-work" commit -qm undocumented
git clone -q --bare "$TMP/invalid-work" "$TMP/invalid.git"

CATALOG_WORK="$TMP/catalog-work"
CATALOG_REMOTE="$TMP/catalog.git"
mkdir -p "$CATALOG_WORK"
git -C "$CATALOG_WORK" init -q
write_plugin_manifest "$CATALOG_WORK" b.okomart Okomart 0.0.1
printf 'import QtQuick\nItem {}\n' >"$CATALOG_WORK/Panel.qml"
printf '%s\r\n%s\r\n%s\r\n' \
  "$TMP/alpha.git" "$TMP/beta.git" "$TMP/invalid.git" \
  >"$CATALOG_WORK/plugins.txt"
git -C "$CATALOG_WORK" add .
git -C "$CATALOG_WORK" commit -qm "initial catalog"
git clone -q --bare "$CATALOG_WORK" "$CATALOG_REMOTE"
git -C "$CATALOG_WORK" remote add origin "$CATALOG_REMOTE"
git -C "$CATALOG_WORK" push -q -u origin main

SOURCE="$TMP/source"
git clone -q --no-recurse-submodules "$CATALOG_REMOTE" "$SOURCE"

COLD_CACHE="$TMP/cached-empty.json"
"$OKOMART" cached >"$COLD_CACHE"
assert_jq "$COLD_CACHE" \
  '(.ok|not) and (.cached|not)
    and .error=="No valid cached Okomart snapshot is available."' \
  "cache lookup reports an empty state without refreshing"

INVALID_CACHE_STATE="$TMP/invalid-cache-state"
mkdir -p -- "$INVALID_CACHE_STATE/okomart"
printf '%s\n' \
  '{"ok":false,"snapshotId":"failed-snapshot","plugins":[]}' \
  >"$INVALID_CACHE_STATE/okomart/snapshot.json"
XDG_STATE_HOME="$INVALID_CACHE_STATE" \
  XDG_CACHE_HOME="$TMP/invalid-cache-root" \
  "$OKOMART" cached >"$TMP/cached-invalid.json"
assert_jq "$TMP/cached-invalid.json" \
  '(.ok|not) and (.cached|not)
    and .error=="No valid cached Okomart snapshot is available."' \
  "cache lookup rejects a persisted failed snapshot"

MOCK_LOG="$TMP/omarchy.log"
MOCK_LIST="$TMP/plugin-list.json"
MOCK_OKOMART_SOURCE="$SOURCE"
printf '[]\n' >"$MOCK_LIST"
export MOCK_LOG MOCK_LIST MOCK_OKOMART_SOURCE

MOCK_OMARCHY="$TMP/bin/omarchy"
MOCK_SHELL="$TMP/bin/omarchy-shell"
cat >"$MOCK_OMARCHY" <<'MOCK'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"$MOCK_LOG"
if [[ ${1:-} == plugin && ${2:-} == list && ${3:-} == --json ]]; then
  cat "$MOCK_LIST"
  exit 0
fi
if [[ -n ${MOCK_SLEEP_SECONDS:-} ]]; then
  sleep "$MOCK_SLEEP_SECONDS"
fi
if [[ -n ${MOCK_MUTATE_SNAPSHOT:-}
    && ${1:-} == plugin && ${2:-} == update && ${3:-} == b.alpha ]]; then
  jq '.plugins=[] | .self.safeUpdate=false' "$MOCK_MUTATE_SNAPSHOT" \
    >"${MOCK_MUTATE_SNAPSHOT}.next.$$"
  mv "${MOCK_MUTATE_SNAPSHOT}.next.$$" "$MOCK_MUTATE_SNAPSHOT"
fi
if [[ -n ${MOCK_BREAK_ACTION_STATE:-}
    && ${1:-} == plugin && ${2:-} == update && ${3:-} == b.alpha ]]; then
  rm -f -- "$MOCK_BREAK_ACTION_STATE"
  mkdir -- "$MOCK_BREAK_ACTION_STATE"
fi
if [[ -n ${MOCK_FAIL_ID:-} && " $* " == *" $MOCK_FAIL_ID "* ]]; then
  printf 'mock failure for %s\n' "$MOCK_FAIL_ID" >&2
  exit 7
fi
printf 'mock success\n'
MOCK
cat >"$MOCK_SHELL" <<'MOCK'
#!/usr/bin/env bash
printf 'shell:%s\n' "$*" >>"$MOCK_LOG"
if [[ ${1:-} == shell && ${2:-} == call
    && ${3:-} == b.okomart && ${4:-} == runtimeVersion ]]; then
  if [[ -n ${MOCK_RUNTIME_VERSION+x} ]]; then
    printf '%s\n' "$MOCK_RUNTIME_VERSION"
  else
    jq -r '.version // ""' "$MOCK_OKOMART_SOURCE/manifest.json"
  fi
  exit 0
fi
printf 'ok\n'
MOCK
chmod +x "$MOCK_OMARCHY" "$MOCK_SHELL"
export OKOMART_OMARCHY_BIN="$MOCK_OMARCHY"
export OKOMART_SHELL_BIN="$MOCK_SHELL"

ANCESTOR_SOURCE_ROOT="$TMP/ancestor-source-root"
ANCESTOR_SOURCE="$ANCESTOR_SOURCE_ROOT/b.okomart"
mkdir -p "$ANCESTOR_SOURCE"
git -C "$ANCESTOR_SOURCE_ROOT" init -q
cp -- "$CATALOG_WORK/manifest.json" "$CATALOG_WORK/Panel.qml" \
  "$CATALOG_WORK/plugins.txt" "$ANCESTOR_SOURCE/"
git -C "$ANCESTOR_SOURCE_ROOT" add b.okomart
git -C "$ANCESTOR_SOURCE_ROOT" commit -qm \
  "track copied Okomart folder from ancestor"
git -C "$ANCESTOR_SOURCE_ROOT" remote add origin "$CATALOG_REMOTE"
if XDG_CACHE_HOME="$TMP/ancestor-source-cache" \
  XDG_STATE_HOME="$TMP/ancestor-source-state" \
  "$OKOMART" snapshot "$ANCESTOR_SOURCE" \
  >"$TMP/snapshot-ancestor-source.json"; then
  fail "ancestor-managed Okomart source should not inherit its parent origin"
fi
assert_jq "$TMP/snapshot-ancestor-source.json" \
  '(.ok|not) and .stale
    and .error=="The Okomart source checkout has no catalog origin."
    and .self.installType=="local"
    and .self.updateState=="non-git"
    and .self.currentCommit=="" and .self.availableCommit==""
    and (.self.safeUpdate|not)' \
  "Okomart ignores ancestor Git metadata for catalog and self updates"

LINKED_OKOMART_SOURCE="$TMP/linked-okomart-source"
git -C "$CATALOG_WORK" worktree add -q --detach "$LINKED_OKOMART_SOURCE" HEAD
if XDG_CACHE_HOME="$TMP/linked-source-cache" \
  XDG_STATE_HOME="$TMP/linked-source-state" \
  "$OKOMART" snapshot "$LINKED_OKOMART_SOURCE" \
  >"$TMP/snapshot-linked-source.json"; then
  fail "linked-worktree Okomart source should not be advertised as updatable"
fi
assert_jq "$TMP/snapshot-linked-source.json" \
  '(.ok|not) and .stale
    and .error=="The Okomart source checkout has no catalog origin."
    and .self.installType=="local"
    and .self.updateState=="non-git"
    and .self.currentCommit=="" and .self.availableCommit==""
    and (.self.safeUpdate|not)' \
  "Okomart rejects linked-worktree metadata that target updates cannot use"

if env -u OKOMART_TEST_ALLOW_LOCAL_REGISTRY_URLS \
  XDG_CACHE_HOME="$TMP/public-url-cache" \
  XDG_STATE_HOME="$TMP/public-url-state" \
  "$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-local-url-rejected.json"; then
  fail "production registry validation should reject local repository paths"
fi
assert_jq "$TMP/snapshot-local-url-rejected.json" \
  '(.ok|not) and .stale
    and .error=="The catalog plugins.txt registry is invalid."' \
  "production registry validation requires public HTTPS URLs"

registry_contract_index=0
for malformed_registry_url in \
  "https://example.com/%2e%2e/plugin.git" \
  "https://127.000.000.001/plugin.git" \
  "https://[:::]/plugin.git" \
  "https://example.com/café.git"; do
  registry_contract_index=$((registry_contract_index + 1))
  printf '%s\n' "$malformed_registry_url" >"$CATALOG_WORK/plugins.txt"
  git -C "$CATALOG_WORK" add plugins.txt
  git -C "$CATALOG_WORK" commit -qm \
    "noncanonical registry URL fixture $registry_contract_index"
  git -C "$CATALOG_WORK" push -q origin main
  if env -u OKOMART_TEST_ALLOW_LOCAL_REGISTRY_URLS \
    XDG_CACHE_HOME="$TMP/noncanonical-cache-$registry_contract_index" \
    XDG_STATE_HOME="$TMP/noncanonical-state-$registry_contract_index" \
    "$OKOMART" snapshot "$SOURCE" \
    >"$TMP/snapshot-noncanonical-$registry_contract_index.json"; then
    fail "production registry validation accepted '$malformed_registry_url'"
  fi
  assert_jq "$TMP/snapshot-noncanonical-$registry_contract_index.json" \
    '(.ok|not) and .stale
      and .error=="The catalog plugins.txt registry is invalid."' \
    "production registry rejects noncanonical URL case $registry_contract_index"
done

printf '%s\r\n%s\r\n%s\r\n' \
  "$TMP/alpha.git" "$TMP/beta.git" "$TMP/invalid.git" \
  >"$CATALOG_WORK/plugins.txt"
git -C "$CATALOG_WORK" add plugins.txt
git -C "$CATALOG_WORK" commit -qm "restore local registry fixture"
git -C "$CATALOG_WORK" push -q origin main

SNAP1="$TMP/snapshot-1.json"
"$OKOMART" snapshot "$SOURCE" >"$SNAP1"
assert_jq "$SNAP1" \
  '.ok and (.stale|not) and (.plugins|length)==2
    and (.catalogErrors|length)==1
    and .catalogErrors[0].error
      =="Catalog manifests require nonblank name, author, and description"' \
  "initial CRLF registry rejects entries without README metadata"
assert_jq "$SNAP1" \
  '.changes == {added:[],removed:[],updated:[]}' \
  "first bootstrap does not mark every catalog entry new"
assert_jq "$SNAP1" \
  '[.plugins[]|select(.id=="b.alpha")][0]
    | .version=="1.0.0"
      and (.images|length)==3
      and (.images[0]|endswith("/shot1.jpg"))
      and (.images[1]|endswith("/screenshots/shot2.PNG"))
      and (.images[2]|endswith("/images/shot10.png"))
      and .updatedAt=='"$ALPHA_V1_UPDATED_AT"'' \
  "root, images, and screenshots files are filtered and naturally ordered"
assert_jq "$SNAP1" \
  '([.plugins[]|select(.id=="b.beta")][0].images|length)==1' \
  "a single supported screenshot is exposed without carousel padding"

: >"$TIMEOUT_LOG"
CACHED1="$TMP/cached-1.json"
"$OKOMART" cached >"$CACHED1"
assert_jq "$CACHED1" \
  '.ok and .cached and (.plugins|length)==2
    and .snapshotId=="'"$(jq -r .snapshotId "$SNAP1")"'"
    and .catalogCommit=="'"$(jq -r .catalogCommit "$SNAP1")"'"' \
  "cache lookup returns the persisted actionable snapshot"
[[ ! -s $TIMEOUT_LOG ]] ||
  fail "cache lookup performed network work"
pass "cache lookup performs no network work"

ALPHA_CACHE_KEY="$(printf '%s' "$TMP/alpha.git" | sha256sum | awk '{print $1}')"
ALPHA_CACHE_MIRROR="$XDG_CACHE_HOME/okomart/repositories/$ALPHA_CACHE_KEY.git"
ALPHA_PARENT="$(git -C "$TMP/alpha-work" rev-parse "$ALPHA_V1^")"
assert_eq "true" \
  "$(git -C "$ALPHA_CACHE_MIRROR" rev-parse --is-shallow-repository)" \
  "deep-history plugin cache is shallow"
assert_eq "1" "$(git -C "$ALPHA_CACHE_MIRROR" rev-list --all --count)" \
  "deep-history plugin cache retains only the selected HEAD commit"
if git -C "$ALPHA_CACHE_MIRROR" cat-file -e "$ALPHA_PARENT^{commit}" \
  >/dev/null 2>&1; then
  fail "deep-history plugin cache retained the selected commit's parent"
fi
pass "deep-history plugin cache omits prior commit objects"
assert_eq "true" \
  "$(git -C "$XDG_CACHE_HOME/okomart/registry.git" \
    rev-parse --is-shallow-repository)" \
  "catalog registry cache is shallow"
assert_eq "1" \
  "$(git -C "$XDG_CACHE_HOME/okomart/registry.git" rev-list --all --count)" \
  "catalog registry cache retains only the selected HEAD commit"
INITIAL_ALPHA_DISPLAY="$(
  jq -r '[.plugins[]|select(.id=="b.alpha")][0].images[0]' "$SNAP1"
)"
INITIAL_ALPHA_DISPLAY="$(dirname -- "$(dirname -- "$INITIAL_ALPHA_DISPLAY")")"
[[ ! -e $XDG_CACHE_HOME/okomart/catalog/.git &&
  ! -e $INITIAL_ALPHA_DISPLAY/.git ]] ||
  fail "display materialization duplicated a Git object database"
pass "catalog and plugin display trees materialize files without Git history"
: >"$TIMEOUT_LOG"
"$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-unchanged-cache.json"
assert_jq "$TMP/snapshot-unchanged-cache.json" \
  '(.stale|not) and .changes=={added:[],removed:[],updated:[]}' \
  "unchanged shallow mirrors still produce a current catalog"
if grep -F '/.mirror.tmp.' "$TIMEOUT_LOG" | grep -F ' fetch ' >/dev/null; then
  fail "unchanged catalog refresh re-downloaded a cached HEAD tree"
fi
pass "unchanged refresh reuses validated shallow mirrors after bounded HEAD checks"
export MOCK_TAR_FAILURE=1
"$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-tar-failure.json"
unset MOCK_TAR_FAILURE
assert_jq "$TMP/snapshot-tar-failure.json" \
  '.ok and .stale
    and .error=="Could not prepare the catalog display checkout."
    and .catalogCommit=="'"$(jq -r .catalogCommit "$SNAP1")"'"' \
  "tree materialization detects tar pipeline failure and preserves stale state"
git -C "$ALPHA_CACHE_MIRROR" fetch -q --unshallow origin \
  '+HEAD:refs/heads/okomart-cache'
(( $(git -C "$ALPHA_CACHE_MIRROR" rev-list --all --count) >= 82 )) ||
  fail "legacy full-history mirror fixture was not prepared"
"$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-legacy-mirror-repaired.json"
assert_eq "true" \
  "$(git -C "$ALPHA_CACHE_MIRROR" rev-parse --is-shallow-repository)" \
  "legacy full-history plugin cache is replaced by a shallow mirror"
assert_eq "1" "$(git -C "$ALPHA_CACHE_MIRROR" rev-list --all --count)" \
  "legacy mirror migration drops downloaded plugin history"

INITIAL_CATALOG_COMMIT="$(jq -r '.catalogCommit' "$SNAP1")"
INITIAL_SCREENSHOT_PATH="$(
  jq -r '[.plugins[]|select(.id=="b.alpha")][0].images[0]' "$SNAP1"
)"
INITIAL_SCREENSHOT_SHA="$(
  sha256sum "$INITIAL_SCREENSHOT_PATH" | awk '{print $1}'
)"
printf 'png-v2' >"$TMP/alpha-work/images/shot2.PNG"
advance_plugin alpha 2.0.0
ALPHA_V2="$(git -C "$TMP/alpha-work" rev-parse HEAD)"
ALPHA_V2_UPDATED_AT="$(git -C "$TMP/alpha-work" show -s --format=%ct "$ALPHA_V2")"
printf '%s\n%s\n%s\n' \
  "$TMP/invalid.git" "$TMP/beta.git" "$TMP/alpha.git" \
  >"$CATALOG_WORK/plugins.txt"
printf 'Generated catalog README\n' >"$CATALOG_WORK/README.md"
git -C "$CATALOG_WORK" add plugins.txt README.md
git -C "$CATALOG_WORK" commit -qm "catalog timeout fixture"
git -C "$CATALOG_WORK" push -q origin main
TIMEOUT_FIXTURE_COMMIT="$(git -C "$CATALOG_WORK" rev-parse HEAD)"
: >"$TIMEOUT_LOG"
export MOCK_TIMEOUT_PLUGIN_FETCH=1
if ! "$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-timeout.json"; then
  cat "$TMP/snapshot-timeout.json" >&2
  fail "a timed-out refresh lost its valid stale catalog"
fi
unset MOCK_TIMEOUT_PLUGIN_FETCH
assert_jq "$TMP/snapshot-timeout.json" \
  '.ok and .stale and (.error|length>0)
    and .catalogCommit=="'"$INITIAL_CATALOG_COMMIT"'"' \
  "a timed-out plugin fetch retains the last valid catalog"
TIMEOUT_PLUGIN_CALL="$(
  grep -F '/.mirror.tmp.plugin.' "$TIMEOUT_LOG" |
    grep -F ' fetch ' | head -1 || true
)"
[[ $TIMEOUT_PLUGIN_CALL == \
  "3s git -C $XDG_CACHE_HOME/okomart/.mirror.tmp.plugin."*".git fetch "* ]] ||
  fail "plugin repository fetch did not use the configured timeout"
pass "plugin repository fetch uses the configured timeout"
assert_stale_cache_integrity \
  "$TMP/snapshot-timeout.json" \
  "$INITIAL_SCREENSHOT_PATH" \
  "$INITIAL_SCREENSHOT_SHA" \
  "timed-out catalog refresh"

"$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-timeout-recovered.json"
assert_jq "$TMP/snapshot-timeout-recovered.json" \
  '(.stale|not) and .catalogCommit=="'"$TIMEOUT_FIXTURE_COMMIT"'"
    and .changes.updated==["b.alpha"]
    and ([.plugins[]|select(.id=="b.alpha")][0]
      | .version=="2.0.0" and .catalogCommit=="'"$ALPHA_V2"'")' \
  "catalog refresh recovers and follows the plugin repository HEAD"
assert_jq "$TMP/snapshot-timeout-recovered.json" \
  '.self.updateState=="catalog-current"
    and (.self.appChanged|not) and (.self.safeUpdate|not)' \
  "plugins.txt and generated README changes remain catalog-only"
assert_eq "1" "$(git -C "$ALPHA_CACHE_MIRROR" rev-list --all --count)" \
  "plugin mirror replacement does not accumulate prior shallow HEADs"
if git -C "$ALPHA_CACHE_MIRROR" cat-file -e "$ALPHA_V1^{commit}" \
  >/dev/null 2>&1; then
  fail "plugin mirror replacement retained the previous shallow HEAD"
fi
pass "plugin mirror replacement discards the previous shallow HEAD object"
VALID_SCREENSHOT_PATH="$(
  jq -r '[.plugins[]|select(.id=="b.alpha")][0].images[0]' \
    "$TMP/snapshot-timeout-recovered.json"
)"
VALID_SCREENSHOT_SHA="$(
  sha256sum "$VALID_SCREENSHOT_PATH" | awk '{print $1}'
)"

cp -- "$CATALOG_WORK/plugins.txt" "$TMP/valid-plugins.txt"
printf '%s\n%s\n' "$TMP/alpha.git" "not-a-plugin-url" \
  >"$CATALOG_WORK/plugins.txt"
git -C "$CATALOG_WORK" add plugins.txt
git -C "$CATALOG_WORK" commit -qm "malformed plugin registry fixture"
git -C "$CATALOG_WORK" push -q origin main
"$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-malformed-registry.json"
assert_jq "$TMP/snapshot-malformed-registry.json" \
  '.ok and .stale and (.error|length>0)
    and .catalogCommit=="'"$TIMEOUT_FIXTURE_COMMIT"'"
    and ([.plugins[].id]|sort)==["b.alpha","b.beta"]' \
  "a malformed registry URL fails refresh without replacing the valid catalog"
assert_jq "$XDG_STATE_HOME/okomart/catalog.json" \
  '.catalogCommit=="'"$TIMEOUT_FIXTURE_COMMIT"'"
    and ([.entries[].id]|sort)==["b.alpha","b.beta"]' \
  "a malformed registry leaves the persisted valid catalog unchanged"
assert_stale_cache_integrity \
  "$TMP/snapshot-malformed-registry.json" \
  "$VALID_SCREENSHOT_PATH" \
  "$VALID_SCREENSHOT_SHA" \
  "malformed catalog refresh"

if XDG_CACHE_HOME="$TMP/cold-cache" XDG_STATE_HOME="$TMP/cold-state" \
  "$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-malformed-cold.json"; then
  fail "a cold malformed catalog should not produce a successful snapshot"
fi
assert_jq "$TMP/snapshot-malformed-cold.json" \
  '(.ok|not) and .stale and (.error|length>0)
    and .catalogCommit=="" and (.plugins|length)==0' \
  "a malformed catalog on cold cache fails closed with no invented entries"

printf '%s\n\n%s\n' "$TMP/alpha.git" "$TMP/beta.git" \
  >"$CATALOG_WORK/plugins.txt"
git -C "$CATALOG_WORK" add plugins.txt
git -C "$CATALOG_WORK" commit -qm "blank plugin registry line fixture"
git -C "$CATALOG_WORK" push -q origin main
"$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-blank-registry.json"
assert_jq "$TMP/snapshot-blank-registry.json" \
  '.ok and .stale and (.error|length>0)
    and .catalogCommit=="'"$TIMEOUT_FIXTURE_COMMIT"'"' \
  "blank registry lines fail refresh without publishing partial content"

printf '%s\n%s\n' "$TMP/alpha.git" "$TMP/alpha.git" \
  >"$CATALOG_WORK/plugins.txt"
git -C "$CATALOG_WORK" add plugins.txt
git -C "$CATALOG_WORK" commit -qm "duplicate plugin URL fixture"
git -C "$CATALOG_WORK" push -q origin main
"$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-duplicate-registry.json"
assert_jq "$TMP/snapshot-duplicate-registry.json" \
  '.ok and .stale and (.error|length>0)
    and .catalogCommit=="'"$TIMEOUT_FIXTURE_COMMIT"'"' \
  "duplicate registry URLs fail refresh without publishing partial content"

cp -- "$TMP/valid-plugins.txt" "$CATALOG_WORK/plugins.txt"
git -C "$CATALOG_WORK" add plugins.txt
git -C "$CATALOG_WORK" commit -qm "restore valid plugin registry"
git -C "$CATALOG_WORK" push -q origin main
"$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-registry-recovered.json"
assert_jq "$TMP/snapshot-registry-recovered.json" \
  '(.stale|not) and (.plugins|length)==2' \
  "catalog refresh recovers after plugins.txt is repaired"
RECOVERED_ALPHA_IMAGE="$(
  jq -r '[.plugins[]|select(.id=="b.alpha")][0].images[0]' \
    "$TMP/snapshot-registry-recovered.json"
)"
printf '%s\n%s\n%s\n' \
  "$TMP/alpha.git" "$TMP/invalid.git" "$TMP/beta.git" \
  >"$CATALOG_WORK/plugins.txt"
git -C "$CATALOG_WORK" add plugins.txt
git -C "$CATALOG_WORK" commit -qm "reorder plugin registry"
git -C "$CATALOG_WORK" push -q origin main
"$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-registry-reordered.json"
assert_jq "$TMP/snapshot-registry-reordered.json" \
  '.changes == {added:[],removed:[],updated:[]}' \
  "registry reordering does not invent plugin changes"
assert_jq "$TMP/snapshot-registry-reordered.json" \
  '[.plugins[]|select(.id=="b.alpha")][0].images[0]
    == "'"$RECOVERED_ALPHA_IMAGE"'"' \
  "URL-hashed display paths remain stable across registry reordering"

printf '// Okomart development-link update fixture\n' >>"$CATALOG_WORK/Panel.qml"
git -C "$CATALOG_WORK" add Panel.qml
git -C "$CATALOG_WORK" commit -qm "development-link application update fixture"
git -C "$CATALOG_WORK" push -q origin main
DEV_LINK_SOURCE_COMMIT="$(git -C "$SOURCE" rev-parse HEAD)"
git -C "$SOURCE" fetch -q --no-recurse-submodules origin HEAD
DEV_LINK_REMOTE_COMMIT="$(git -C "$SOURCE" rev-parse FETCH_HEAD)"
assert_eq \
  "$(git -C "$CATALOG_WORK" rev-parse HEAD)" \
  "$DEV_LINK_REMOTE_COMMIT" \
  "development-link fixture fetched the pushed remote application commit"
if ! git -C "$SOURCE" diff --name-only "$DEV_LINK_SOURCE_COMMIT" \
  "$DEV_LINK_REMOTE_COMMIT" -- Panel.qml | grep -qx Panel.qml; then
  fail "development-link fixture is missing its remote application update"
fi
pass "development-link fixture has a real application update ahead"
ln -s "$SOURCE" "$TMP/source-development-link"
DEV_LINK_VARIANTS=(
  "$TMP/source-development-link/"
  "$TMP/source-development-link//"
  "$TMP/source-development-link/."
)
DEV_LINK_INDEX=0
for DEV_LINK_ARG in "${DEV_LINK_VARIANTS[@]}"; do
  DEV_LINK_INDEX=$((DEV_LINK_INDEX + 1))
  DEV_LINK_SNAPSHOT="$TMP/snapshot-self-development-link-$DEV_LINK_INDEX.json"
  DEV_LINK_ACTION="$TMP/action-self-development-link-$DEV_LINK_INDEX.json"
  : >"$MOCK_LOG"
  "$OKOMART" snapshot "$DEV_LINK_ARG" >"$DEV_LINK_SNAPSHOT"
  assert_jq "$DEV_LINK_SNAPSHOT" \
    '.self.developmentLink
      and .self.installType=="development-link"
      and .self.updateState=="development-link"
      and (.self.safeUpdate|not)
      and .self.currentCommit=="'"$DEV_LINK_SOURCE_COMMIT"'"
      and .self.availableCommit==""' \
    "Okomart preserves development-link source spelling $DEV_LINK_INDEX"
  export OKOMART_ACTION_FOREGROUND=1
  "$OKOMART" action "$DEV_LINK_ARG" update-all "" \
    "$(jq -r '.snapshotId' "$DEV_LINK_SNAPSHOT")" >"$DEV_LINK_ACTION"
  unset OKOMART_ACTION_FOREGROUND
  [[ -z $(grep '^plugin update b.okomart ' "$MOCK_LOG" || true) ]] ||
    fail "development-link source spelling $DEV_LINK_INDEX invoked self-update"
  pass "development-link source spelling $DEV_LINK_INDEX is excluded from update-all"
done
SAME_VERSION_SELF_SNAPSHOT="$TMP/snapshot-self-same-version.json"
"$OKOMART" snapshot "$SOURCE" >"$SAME_VERSION_SELF_SNAPSHOT"
assert_jq "$SAME_VERSION_SELF_SNAPSHOT" \
  '.self.updateState=="catalog-current"
    and .self.appChanged
    and (.self.versionUpdateAvailable|not)
    and (.self.safeUpdate|not)
    and .self.installedVersion==.self.availableVersion' \
  "Okomart ignores application commits without a manifest version bump"
git -C "$SOURCE" pull -q --ff-only

git clone -q "$TMP/alpha.git" "$OKOMART_PLUGINS_DIR/b.alpha"
git -C "$OKOMART_PLUGINS_DIR/b.alpha" checkout -q "$ALPHA_V1"
git clone -q "$TMP/beta.git" "$OKOMART_PLUGINS_DIR/b.beta"
git clone -q "$TMP/samever.git" "$OKOMART_PLUGINS_DIR/b.samever"
advance_plugin_without_version samever
git clone -q "$TMP/dirty.git" "$OKOMART_PLUGINS_DIR/b.dirty"
printf '// dirty\n' >>"$OKOMART_PLUGINS_DIR/b.dirty/Panel.qml"
git clone -q "$TMP/ahead.git" "$OKOMART_PLUGINS_DIR/b.ahead"
printf '// local commit\n' >>"$OKOMART_PLUGINS_DIR/b.ahead/Panel.qml"
git -C "$OKOMART_PLUGINS_DIR/b.ahead" add Panel.qml
git -C "$OKOMART_PLUGINS_DIR/b.ahead" commit -qm "local ahead"
git clone -q "$TMP/split.git" "$OKOMART_PLUGINS_DIR/b.split"
printf '// local branch\n' >>"$OKOMART_PLUGINS_DIR/b.split/Panel.qml"
git -C "$OKOMART_PLUGINS_DIR/b.split" add Panel.qml
git -C "$OKOMART_PLUGINS_DIR/b.split" commit -qm "local side"
advance_plugin split 2.0.0
git -C "$TMP/linked-work" worktree add -q --detach \
  "$OKOMART_PLUGINS_DIR/b.linked" HEAD
mkdir -p "$TMP/dev-target"
write_plugin_manifest "$TMP/dev-target" b.dev Development 0.1.0
printf 'import QtQuick\nItem {}\n' >"$TMP/dev-target/Panel.qml"
mkdir -p "$TMP/dev-target/images/nested" "$TMP/dev-target/screenshots/nested"
printf 'webp' >"$TMP/dev-target/shot1.webp"
printf 'png' >"$TMP/dev-target/images/shot10.png"
printf 'jpg' >"$TMP/dev-target/screenshots/shot2.JPG"
printf 'ignored' >"$TMP/dev-target/images/readme.txt"
printf 'ignored' >"$TMP/dev-target/images/nested/shot1.png"
printf 'ignored' >"$TMP/dev-target/screenshots/nested/shot0.png"
ln -s "$TMP/dev-target" "$OKOMART_PLUGINS_DIR/b.dev"
mkdir -p "$OKOMART_PLUGINS_DIR/b.broken"
printf '{}\n' >"$OKOMART_PLUGINS_DIR/b.broken/manifest.json"
# Model a dotfiles-style ancestor repository. b.parented is tracked by the
# ancestor, but is intentionally not a Git worktree of its own.
git -C "$OKOMART_PLUGINS_DIR" init -q
mkdir -p "$OKOMART_PLUGINS_DIR/b.parented"
write_plugin_manifest \
  "$OKOMART_PLUGINS_DIR/b.parented" b.parented Parented 0.4.0
printf 'import QtQuick\nItem {}\n' \
  >"$OKOMART_PLUGINS_DIR/b.parented/Panel.qml"
git -C "$OKOMART_PLUGINS_DIR" add b.parented
git -C "$OKOMART_PLUGINS_DIR" commit -qm \
  "track local plugin from ancestor worktree"
printf 'unrelated dotfile edit\n' \
  >"$OKOMART_PLUGINS_DIR/unrelated-dotfile"
printf '[{"id":"b.alpha","enabled":true}]\n' >"$MOCK_LIST"

SNAP2="$TMP/snapshot-installed.json"
"$OKOMART" snapshot "$SOURCE" >"$SNAP2"
assert_jq "$SNAP2" \
  '[.plugins[]|select(.id=="b.alpha")][0]
    | .installed and .enabled and .safeUpdate
      and .updateState=="update-available"
      and .versionUpdateAvailable
      and .installedVersion=="1.0.0"
      and .availableVersion=="2.0.0"
      and .updatedAt=='"$ALPHA_V2_UPDATED_AT"'' \
  "installed Git plugin detects a clean fast-forward update"
assert_jq "$SNAP2" \
  '[.plugins[]|select(.id=="b.ahead")][0].updatedAt
    == '"$(git -C "$OKOMART_PLUGINS_DIR/b.ahead" show -s --format=%ct HEAD)" \
  "installed-only Git plugins expose their latest commit timestamp"
assert_jq "$SNAP2" \
  '[.plugins[]|select(.id=="b.samever")][0]
    | .installed and .remoteRelation=="behind"
      and .updateState=="up-to-date"
      and (.versionUpdateAvailable|not)
      and (.safeUpdate|not)
      and .installedVersion=="1.0.0"
      and .availableVersion=="1.0.0"' \
  "code-only commits do not become plugin updates without a version bump"
assert_jq "$SNAP2" \
  '[.plugins[]|select(.id=="b.dev")][0]
    | .external and .installType=="development-link"
      and .updateState=="development-link"' \
  "development links remain visible with restricted updates"
assert_jq "$SNAP2" \
  '[.plugins[]|select(.id=="b.dev")][0].images
    | length==3
      and (.[0]|endswith("/shot1.webp"))
      and (.[1]|endswith("/screenshots/shot2.JPG"))
      and (.[2]|endswith("/images/shot10.png"))' \
  "installed-only plugins scan every supported screenshot location"
assert_jq "$SNAP2" \
  '[.plugins[]|select(.id=="b.broken")][0]
    | .external and (.manifestValid|not) and .updateState=="invalid"' \
  "malformed local installs remain visible as invalid"
assert_jq "$SNAP2" \
  '[.plugins[]|select(.id=="b.parented")][0]
    | .external and .installed and .installType=="local"
      and .updateState=="non-git"
      and .currentCommit=="" and .sourceUrl==""
      and (.dirty|not) and (.safeUpdate|not)' \
  "a plugin tracked only by an ancestor worktree remains a local install"
assert_jq "$SNAP2" \
  '[.plugins[]|select(.id=="b.linked")][0]
    | .external and .installed and .installType=="local"
      and .updateState=="non-git"
      and .currentCommit=="" and (.safeUpdate|not)' \
  "a linked worktree remains local when Omarchy cannot update its .git file"
assert_jq "$SNAP2" \
  '([.plugins[]|select(.id=="b.dirty")][0].updateState=="dirty")
    and ([.plugins[]|select(.id=="b.ahead")][0].updateState=="ahead")
    and ([.plugins[]|select(.id=="b.split")][0].updateState=="diverged")
    and ([.plugins[]|select(.id=="b.dirty")][0].safeUpdate|not)
    and ([.plugins[]|select(.id=="b.ahead")][0].safeUpdate|not)
    and ([.plugins[]|select(.id=="b.split")][0].safeUpdate|not)' \
  "dirty, locally ahead, and diverged checkouts are separately blocked"

[[ -f $OKOMART_PLUGINS_DIR/b.beta/images/only.webp ]] ||
  fail "beta tombstone zero-image fixture is missing its installed screenshot"
rm -f -- "$OKOMART_PLUGINS_DIR/b.beta/images/only.webp"
git -C "$OKOMART_PLUGINS_DIR/b.beta" add -u
git -C "$OKOMART_PLUGINS_DIR/b.beta" commit -qm \
  "installed plugin removes its screenshot"
git -C "$OKOMART_PLUGINS_DIR/b.beta" push -q origin main
git -C "$TMP/beta-work" pull -q --ff-only origin main
advance_plugin alpha 3.0.0
printf '%s\n%s\n%s\n' \
  "$TMP/alpha.git" "$TMP/invalid.git" "$TMP/gamma.git" \
  >"$CATALOG_WORK/plugins.txt"
printf 'Generated catalog README after registry changes\n' \
  >"$CATALOG_WORK/README.md"
git -C "$CATALOG_WORK" add plugins.txt README.md
git -C "$CATALOG_WORK" commit -qm "refresh catalog entries"
git -C "$CATALOG_WORK" push -q origin main

SNAP3="$TMP/snapshot-changes.json"
"$OKOMART" snapshot "$SOURCE" >"$SNAP3"
assert_jq "$SNAP3" \
  '.changes.added==["b.gamma"]
    and .changes.removed==["b.beta"]
    and .changes.updated==["b.alpha"]' \
  "catalog changes distinguish URL additions, removals, and HEAD updates"
assert_jq "$SNAP3" \
  '[.plugins[]|select(.id=="b.beta")][0]
    | .installed and .removed and (.catalog|not) and (.external|not)' \
  "an installed removed catalog entry remains as a tombstone"
assert_jq "$SNAP3" \
  '([.plugins[]|select(.id=="b.beta")][0].images|length)==0' \
  "a removed catalog tombstone treats the installed zero-image state as authoritative"
assert_jq "$SNAP3" \
  '.self.updateState=="catalog-current"
    and (.self.appChanged|not) and (.self.safeUpdate|not)' \
  "catalog-only commits do not appear as an Okomart application update"
assert_jq "$SNAP3" \
  '([.plugins[]|select(.id=="b.gamma")][0].images|length)==0' \
  "plugins without screenshots expose an empty section model"

printf '\n' >>"$SOURCE/plugins.txt"
"$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-catalog-dirty.json"
assert_jq "$TMP/snapshot-catalog-dirty.json" \
  '.self.updateState=="catalog-current"
    and .self.repositoryDirty and (.self.dirty|not) and (.self.safeUpdate|not)' \
  "catalog-only working-tree dirt does not create a false Okomart update"
git -C "$SOURCE" checkout -q -- plugins.txt

mv "$CATALOG_REMOTE" "$TMP/catalog-offline.git"
SNAP4="$TMP/snapshot-offline.json"
"$OKOMART" snapshot "$SOURCE" >"$SNAP4"
assert_jq "$SNAP4" \
  '.ok and .stale and (.error|length>0)
    and .catalogCommit=="'"$(jq -r .catalogCommit "$SNAP3")"'"' \
  "offline refresh retains and labels the last valid catalog snapshot"
assert_jq "$SNAP4" \
  '[.plugins[]|select(.id=="b.beta")][0]
    | .installed and .removed and (.external|not)' \
  "installed catalog removals remain tombstones across later snapshots"

jq -cn '{
  ok:true,running:true,action:"update-all",actionId:"abandoned-fixture",
  pid:424242,startedAt:"2026-01-01T00:00:00Z",finishedAt:"",
  message:"Working…",results:[],resummoned:false,acknowledged:false
}' >"$XDG_STATE_HOME/okomart/action.json"
"$OKOMART" status >"$TMP/status-abandoned.json"
assert_jq "$TMP/status-abandoned.json" \
  '(.ok|not) and (.running|not) and .abandoned
    and .actionId=="abandoned-fixture"
    and (.finishedAt|length>0) and (.acknowledged|not)
    and (.results|length)==1
    and .results[0].id=="worker"
    and .results[0].operation=="update-all"
    and (.results[0].ok|not)
    and (.results[0].output|contains("stopped before completing"))' \
  "status reconciles an abandoned worker with a visible failed result"
ABANDONED_FINISHED_AT="$(jq -r '.finishedAt' "$TMP/status-abandoned.json")"
"$OKOMART" status >"$TMP/status-abandoned-again.json"
assert_jq "$TMP/status-abandoned-again.json" \
  '.abandoned and (.running|not)
    and .finishedAt=="'"$ABANDONED_FINISHED_AT"'"' \
  "abandoned action reconciliation persists one stable terminal record"

CONFIRMED_SNAPSHOT_ID="$(jq -r '.snapshotId' "$SNAP4")"
if "$OKOMART" action "$SOURCE" install b.gamma stale-snapshot \
  >"$TMP/action-stale.json"; then
  fail "an action should not start against a snapshot the user did not confirm"
fi
assert_jq "$TMP/action-stale.json" \
  '(.ok|not) and (.started|not) and .staleConfirmation' \
  "actions are bound to the exact snapshot shown during confirmation"

rm -f -- "$XDG_STATE_HOME/okomart/action.json"
mkdir "$XDG_STATE_HOME/okomart/action.json"
if "$OKOMART" action "$SOURCE" install b.gamma "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-state-failure.json"; then
  fail "an action should not start when queued status cannot be persisted"
fi
assert_jq "$TMP/action-state-failure.json" \
  '(.ok|not) and (.error|contains("persist"))' \
  "action startup fails closed when atomic queued status persistence fails"
rmdir "$XDG_STATE_HOME/okomart/action.json"

: >"$MOCK_LOG"
export OKOMART_ACTION_FOREGROUND=1
"$OKOMART" action "$SOURCE" install b.gamma "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-install.json"
assert_eq \
  "plugin add $TMP/gamma.git --enable --yes" \
  "$(grep '^plugin add ' "$MOCK_LOG")" \
  "install action uses the catalog URL and official add-and-enable CLI"
assert_jq "$TMP/action-install.json" \
  '.ok and (.running|not) and .resummoned and .results[0].id=="b.gamma"' \
  "install action records an atomic successful result and re-summons Okomart"

advance_plugin gamma 2.0.0
: >"$MOCK_LOG"
if "$OKOMART" action "$SOURCE" install b.gamma "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-install-drift.json"; then
  fail "install should stop when the repository moved past the confirmed HEAD"
fi
assert_jq "$TMP/action-install-drift.json" \
  '(.ok|not) and .results[0].id=="b.gamma"
    and (.results[0].output|contains("changed after confirmation"))' \
  "install revalidates remote HEAD against the confirmed catalog commit"
[[ -z $(grep '^plugin add ' "$MOCK_LOG" || true) ]] \
  || fail "remote-drift install invoked the Omarchy CLI"
pass "remote-drift install fails before invoking the Omarchy CLI"

: >"$MOCK_LOG"
[[ -n $(git -C "$OKOMART_PLUGINS_DIR" status --porcelain) ]] ||
  fail "ancestor-worktree removal fixture is not dirty"
"$OKOMART" action "$SOURCE" remove b.parented "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-remove-parented.json"
assert_eq \
  "plugin remove b.parented --yes" \
  "$(grep '^plugin remove ' "$MOCK_LOG")" \
  "local plugin removal ignores unrelated ancestor-worktree changes"
assert_jq "$TMP/action-remove-parented.json" \
  '.ok and (.running|not)
    and .results[0].id=="b.parented"
    and .results[0].operation=="remove"
    and .results[0].ok' \
  "ancestor-managed folder uses local manifest removal preflight"

: >"$MOCK_LOG"
"$OKOMART" action "$SOURCE" remove b.alpha "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-remove.json"
assert_eq \
  "plugin remove b.alpha --yes" \
  "$(grep '^plugin remove ' "$MOCK_LOG")" \
  "remove action uses the official confirmed CLI form"

printf '// changed after confirmation\n' >>"$OKOMART_PLUGINS_DIR/b.alpha/Panel.qml"
: >"$MOCK_LOG"
if "$OKOMART" action "$SOURCE" remove b.alpha "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-remove-changed.json"; then
  fail "remove should stop when the installed checkout changed after confirmation"
fi
assert_jq "$TMP/action-remove-changed.json" \
  '(.ok|not) and (.results[0].output|contains("changed after confirmation"))' \
  "remove revalidates the installed commit and clean state"
[[ -z $(grep '^plugin remove ' "$MOCK_LOG" || true) ]] \
  || fail "changed-checkout remove invoked the Omarchy CLI"
pass "changed-checkout remove fails before invoking the Omarchy CLI"
git -C "$OKOMART_PLUGINS_DIR/b.alpha" checkout -q -- Panel.qml

: >"$MOCK_LOG"
: >"$TIMEOUT_LOG"
export OKOMART_ACTION_TIMEOUT_SECONDS=1
export MOCK_SLEEP_SECONDS=2
if "$OKOMART" action "$SOURCE" remove b.beta "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-timeout.json"; then
  fail "a stalled plugin mutation should reach a terminal failure"
fi
unset MOCK_SLEEP_SECONDS OKOMART_ACTION_TIMEOUT_SECONDS
assert_jq "$TMP/action-timeout.json" \
  '(.ok|not) and (.running|not) and .resummoned
    and (.results[0].output|contains("timed out this remove"))
    and (.results[0].output|contains("partially changed plugin state"))' \
  "stalled plugin mutations time out with a visible terminal result"
MUTATION_TIMEOUT_CALL="$(
  grep -F "$MOCK_OMARCHY plugin remove b.beta --yes" "$TIMEOUT_LOG" \
    | tail -1 || true
)"
[[ $MUTATION_TIMEOUT_CALL == \
  "--signal=TERM --kill-after=5s 1s $MOCK_OMARCHY plugin remove b.beta --yes" ]] \
  || fail "plugin mutation did not use the configured whole-command timeout"
pass "plugin mutations use the configured whole-command timeout"
if flock -n "$XDG_STATE_HOME/okomart/action.lock" true; then
  pass "timed-out plugin mutations release the action lock"
else
  fail "timed-out plugin mutation left the action lock held"
fi
: >"$TIMEOUT_LOG"
for invalid_action_timeout in invalid 3601 999999999999999999999999; do
  export OKOMART_ACTION_TIMEOUT_SECONDS="$invalid_action_timeout"
  "$OKOMART" action "$SOURCE" remove b.beta "$CONFIRMED_SNAPSHOT_ID" \
    >"$TMP/action-timeout-default-$invalid_action_timeout.json"
  jq -e '.ok and (.running|not)' \
    "$TMP/action-timeout-default-$invalid_action_timeout.json" >/dev/null \
    || fail "invalid action timeout setting broke a plugin mutation"
done
unset OKOMART_ACTION_TIMEOUT_SECONDS
[[ $(grep -F -- "--kill-after=5s 300s $MOCK_OMARCHY plugin remove b.beta --yes" \
  "$TIMEOUT_LOG" | wc -l) -eq 3 ]] \
  || fail "invalid action timeout settings did not use the safe default"
pass "invalid and overlarge action timeouts use the bounded default"

: >"$MOCK_LOG"
unset OKOMART_ACTION_FOREGROUND
export MOCK_SLEEP_SECONDS=0.3
"$OKOMART" action "$SOURCE" remove b.beta "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-detached.json"
assert_jq "$TMP/action-detached.json" \
  '.ok and .started and (.pid|type)=="number" and (.statusPath|length>0)' \
  "normal action invocation launches a detached worker"
if "$OKOMART" action "$SOURCE" remove b.alpha "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-busy.json"; then
  fail "a second action should not start while the worker lock is held"
fi
assert_jq "$TMP/action-busy.json" \
  '(.ok|not) and (.started|not) and .busy' \
  "the action lock rejects overlapping plugin mutations"
unset MOCK_SLEEP_SECONDS
for _ in {1..100}; do
  "$OKOMART" status >"$TMP/action-detached-status.json"
  [[ $(jq -r '.running' "$TMP/action-detached-status.json") == false ]] && break
  sleep 0.02
done
assert_jq "$TMP/action-detached-status.json" \
  '(.running|not) and .ok and .resummoned
    and .results[0].operation=="remove"' \
  "detached worker releases the caller and atomically completes in status"

OLD_ACTION_ID="$(jq -r '.actionId' "$TMP/action-detached-status.json")"
export MOCK_SLEEP_SECONDS=0.3
"$OKOMART" action "$SOURCE" remove b.alpha "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-newer.json"
NEW_ACTION_ID="$(jq -r '.actionId' "$TMP/action-newer.json")"
if "$OKOMART" ack "$OLD_ACTION_ID" >"$TMP/ack-racing.json"; then
  fail "an old acknowledgement should not race a newer action"
fi
assert_jq "$TMP/ack-racing.json" \
  '(.ok|not) and .busy and .actionId=="'"$OLD_ACTION_ID"'"' \
  "acknowledgement uses the action lock instead of clobbering newer status"
"$OKOMART" status >"$TMP/status-newer-running.json"
assert_jq "$TMP/status-newer-running.json" \
  '.actionId=="'"$NEW_ACTION_ID"'" and .running
    and ((.abandoned // false)|not)' \
  "status does not abandon a live worker that still holds the action lock"
unset MOCK_SLEEP_SECONDS
for _ in {1..100}; do
  "$OKOMART" status >"$TMP/status-newer-finished.json"
  [[ $(jq -r '.running' "$TMP/status-newer-finished.json") == false ]] && break
  sleep 0.02
done
export OKOMART_ACTION_FOREGROUND=1

mv "$TMP/catalog-offline.git" "$CATALOG_REMOTE"
advance_plugin beta 2.0.0
printf '// Okomart application update fixture\n' >>"$CATALOG_WORK/Panel.qml"
jq '.version="0.0.2"' "$CATALOG_WORK/manifest.json" \
  >"$CATALOG_WORK/manifest.json.next"
mv "$CATALOG_WORK/manifest.json.next" "$CATALOG_WORK/manifest.json"
git -C "$CATALOG_WORK" add Panel.qml manifest.json
git -C "$CATALOG_WORK" commit -qm "application update"
git -C "$CATALOG_WORK" push -q origin main

"$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-safe-updates.json"
CONFIRMED_SNAPSHOT_ID="$(
  jq -r '.snapshotId' "$TMP/snapshot-safe-updates.json"
)"
assert_jq "$TMP/snapshot-safe-updates.json" \
  '([.plugins[]|select(.id=="b.alpha")][0].safeUpdate)
    and ([.plugins[]|select(.id=="b.beta")][0].safeUpdate)
    and .self.safeUpdate
    and .self.versionUpdateAvailable
    and .self.installedVersion=="0.0.1"
    and .self.availableVersion=="0.0.2"' \
  "update fixture contains real confirmed fast-forward commits"

: >"$MOCK_LOG"
"$OKOMART" action "$SOURCE" update b.alpha "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-update-one.json"
assert_eq \
  "plugin update b.alpha --yes" \
  "$(grep '^plugin update ' "$MOCK_LOG")" \
  "single-plugin update uses the official confirmed CLI form"
assert_jq "$TMP/action-update-one.json" \
  '.ok and (.running|not) and (.results|length)==1
    and .results[0].id=="b.alpha"
    and .results[0].operation=="update"
    and .results[0].ok' \
  "single-plugin update changes only the selected plugin"

advance_plugin alpha 4.0.0
: >"$MOCK_LOG"
if "$OKOMART" action "$SOURCE" update-all "" "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-update-drift.json"; then
  fail "update-all should report a remote that changed after confirmation"
fi
assert_eq \
  $'plugin update b.beta --yes\nplugin update b.okomart --yes' \
  "$(grep '^plugin update ' "$MOCK_LOG")" \
  "remote drift blocks only the changed package and preserves official updates"
assert_jq "$TMP/action-update-drift.json" \
  '(.ok|not) and (.results|length)==3
    and (.results[0].ok|not) and .results[1].ok and .results[2].ok
    and (.results[0].output|contains("changed after confirmation"))' \
  "update preflight records commit drift and continues safe packages"

"$OKOMART" snapshot "$SOURCE" >"$TMP/snapshot-current-updates.json"
CONFIRMED_SNAPSHOT_ID="$(
  jq -r '.snapshotId' "$TMP/snapshot-current-updates.json"
)"

: >"$MOCK_LOG"
export MOCK_BREAK_ACTION_STATE="$XDG_STATE_HOME/okomart/action.json"
if "$OKOMART" action "$SOURCE" update-all "" "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-persistence-break.json"; then
  fail "worker should fail when action status persistence breaks"
fi
unset MOCK_BREAK_ACTION_STATE
assert_eq \
  "plugin update b.alpha --yes" \
  "$(grep '^plugin update ' "$MOCK_LOG")" \
  "worker stops scheduling mutations after an intermediate status write failure"
assert_jq "$TMP/action-persistence-break.json" \
  '(.running|not) and .action=="" and .acknowledged' \
  "failed terminal persistence reconciles status to a pollable idle state"
rmdir "$XDG_STATE_HOME/okomart/action.json"

: >"$MOCK_LOG"
export MOCK_FAIL_ID=b.beta
export MOCK_MUTATE_SNAPSHOT="$XDG_STATE_HOME/okomart/snapshot.json"
if "$OKOMART" action "$SOURCE" update-all "" "$CONFIRMED_SNAPSHOT_ID" \
  >"$TMP/action-update.json"; then
  fail "update-all should report a failed individual package"
fi
unset MOCK_FAIL_ID MOCK_MUTATE_SNAPSHOT
assert_jq "$XDG_STATE_HOME/okomart/snapshot.json" \
  '(.plugins|length)==0 and (.self.safeUpdate|not)' \
  "the race fixture changes live snapshot state after the worker starts"
assert_eq \
  $'plugin update b.alpha --yes\nplugin update b.beta --yes\nplugin update b.okomart --yes' \
  "$(grep '^plugin update ' "$MOCK_LOG")" \
  "update-all uses the confirmed snapshot, continues failures, and updates Okomart last"
assert_jq "$TMP/action-update.json" \
  '(.ok|not) and (.running|not) and (.results|length)==3
    and .results[0].ok and (.results[1].ok|not) and .results[2].ok' \
  "update-all persists per-package success and failure results"

"$OKOMART" status >"$TMP/status.json"
assert_jq "$TMP/status.json" \
  '.action=="update-all" and (.running|not) and (.results|length)==3' \
  "status returns the last complete atomic worker state"

: >"$MOCK_LOG"
export MOCK_RUNTIME_VERSION
MOCK_RUNTIME_VERSION="$(jq -r '.version' "$ROOT/manifest.json")"
"$OKOMART" _recover-self-update "$ROOT"
assert_eq \
  $'shell:shell summon b.okomart\nshell:shell call b.okomart runtimeVersion ' \
  "$(cat -- "$MOCK_LOG")" \
  "completed self-update recovery verifies and reopens the updated runtime"

: >"$MOCK_LOG"
MOCK_RUNTIME_VERSION="stale"
export OKOMART_RELAUNCH_ATTEMPTS=2
if "$OKOMART" _recover-self-update "$ROOT"; then
  fail "self-update recovery accepted a stale loaded runtime"
fi
unset OKOMART_RELAUNCH_ATTEMPTS
assert_eq \
  "2" \
  "$(grep -Fc 'shell:shell call b.okomart runtimeVersion ' "$MOCK_LOG")" \
  "self-update recovery retries until the loaded runtime version matches"
unset MOCK_RUNTIME_VERSION

ACTION_ID="$(jq -r '.actionId' "$TMP/status.json")"
"$OKOMART" ack "$ACTION_ID" >"$TMP/ack.json"
assert_jq "$TMP/ack.json" \
  '.ok and .acknowledged and .actionId=="'"$ACTION_ID"'"' \
  "a completed action can be acknowledged by its immutable id"
"$OKOMART" status >"$TMP/status-acknowledged.json"
assert_jq "$TMP/status-acknowledged.json" \
  '.actionId=="'"$ACTION_ID"'" and .acknowledged' \
  "acknowledgement persists so later storefront opens do not replay results"
: >"$MOCK_LOG"
"$OKOMART" _recover-self-update "$ROOT"
[[ ! -s $MOCK_LOG ]] \
  || fail "self-update recovery replayed an acknowledged action"
pass "self-update recovery ignores acknowledged actions"
[[ -z $(find "$XDG_STATE_HOME/okomart/worker" -maxdepth 1 \
  -name 'snapshot-*.json' -print -quit 2>/dev/null) ]] \
  || fail "completed workers left a confirmed snapshot copy behind"
pass "completed workers remove their immutable snapshot copy"

printf '1..%d\n' "$pass_count"
