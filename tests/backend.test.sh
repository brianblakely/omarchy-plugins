#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OKOMART="$ROOT/bin/okomart"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

pass_count=0
fail() { printf 'backend.test.sh: %s\n' "$*" >&2; exit 1; }
pass() { pass_count=$((pass_count + 1)); printf 'ok %d - %s\n' "$pass_count" "$1"; }
assert_jq() {
  local file=$1 expression=$2 message=$3
  jq -e "$expression" "$file" >/dev/null || fail "$message: $(cat -- "$file")"
  pass "$message"
}
assert_eq() {
  [[ $1 == "$2" ]] || fail "$3 (expected '$1', got '$2')"
  pass "$3"
}
run_action_to_completion() {
  local started action_id status_file="$TMP/action-status.json"
  started="$("$OKOMART" action "$@")" || {
    printf '%s\n' "$started" >&2
    return 1
  }
  action_id="$(jq -r '.actionId' <<<"$started")"
  for _ in {1..240}; do
    "$OKOMART" status >"$status_file"
    if jq -e --arg id "$action_id" '.actionId == $id and .running == false' \
        "$status_file" >/dev/null 2>&1 &&
      flock -n "$XDG_STATE_HOME/okomart/action.lock" true; then
      cat -- "$status_file"
      jq -e '.ok == true' "$status_file" >/dev/null
      return
    fi
    sleep 0.05
  done
  fail "action worker did not finish: $(cat -- "$status_file" 2>/dev/null || true)"
}

REAL_GIT=$(command -v git)
export HOME="$TMP/home"
export XDG_CACHE_HOME="$TMP/cache"
export XDG_STATE_HOME="$TMP/state"
export XDG_RUNTIME_DIR="$TMP/runtime"
export MOCK_DATA="$TMP/mock-data"
export MOCK_LOG="$TMP/mock.log"
export MOCK_COUNTER="$TMP/counter"
export MOCK_MAX_COUNTER="$TMP/max-counter"
export MOCK_GIT_LOG="$TMP/git.log"
export MOCK_GENERIC_REPO="$TMP/generic-repository"
export MOCK_PLUGIN_STATES="$TMP/plugin-states.json"
export MOCK_CURL_DELAY=0.08
mkdir -p -- "$HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" \
  "$MOCK_DATA/manifests" "$MOCK_DATA/commits" "$MOCK_DATA/trees" "$TMP/mock-bin"
chmod 700 "$XDG_RUNTIME_DIR"
: >"$MOCK_LOG"; : >"$MOCK_GIT_LOG"; printf '0\n' >"$MOCK_COUNTER"; printf '0\n' >"$MOCK_MAX_COUNTER"
printf '[]\n' >"$MOCK_PLUGIN_STATES"

mkdir -p -- "$XDG_CACHE_HOME/okomart/abandoned-work" "$TMP/outside-cache"
printf 'keep\n' >"$TMP/outside-cache/sentinel"
printf 'stale\n' >"$XDG_CACHE_HOME/okomart/abandoned-work/result"
printf 'stale\n' >"$XDG_CACHE_HOME/okomart/stray-file"
ln -s -- "$TMP/outside-cache" "$XDG_CACHE_HOME/okomart/stray-link"

git -c init.defaultBranch=main init -q "$MOCK_GENERIC_REPO"
git -C "$MOCK_GENERIC_REPO" config user.email test@example.com
git -C "$MOCK_GENERIC_REPO" config user.name Test
mkdir -p -- "$MOCK_GENERIC_REPO/images"
printf 'generic screenshot\n' >"$MOCK_GENERIC_REPO/images/generic.png"
printf 'generic qml\n' >"$MOCK_GENERIC_REPO/Generic.qml"
jq -n '{schemaVersion:1,id:"b.generic",name:"Generic",version:"1.0.0",
  author:"Test",description:"Generic host plugin",license:"MIT",
  kinds:["panel"],entryPoints:{panel:"Generic.qml"}}' \
  >"$MOCK_GENERIC_REPO/manifest.json"
git -C "$MOCK_GENERIC_REPO" add .
GIT_AUTHOR_DATE='2025-01-04T00:00:00Z' GIT_COMMITTER_DATE='2025-01-04T00:00:00Z' \
  git -C "$MOCK_GENERIC_REPO" commit -qm initial
GENERIC_HEAD=$($REAL_GIT -C "$MOCK_GENERIC_REPO" rev-parse HEAD)
GENERIC_TIME=$($REAL_GIT -C "$MOCK_GENERIC_REPO" show -s --format=%ct HEAD)

cat >"$TMP/mock-bin/git" <<'MOCK_GIT'
#!/usr/bin/env bash
set -euo pipefail
args=("$@")
if [[ ${1:-} == ls-remote && "$*" == *https://github.com/* ]]; then
  printf '%s\tHEAD\n' "${MOCK_REMOTE_HEAD:-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee}"
  exit 0
fi
if [[ ${1:-} == clone ]]; then
  original=""
  for index in "${!args[@]}"; do
    if [[ ${args[$index]} == https://git.example.com/catalog/generic.git ]]; then
      original=${args[$index]}
      args[$index]=$MOCK_GENERIC_REPO
    fi
  done
  printf 'clone %s\n' "$original" >>"$MOCK_GIT_LOG"
fi
exec "$REAL_GIT" "${args[@]}"
MOCK_GIT
chmod 755 "$TMP/mock-bin/git"
export REAL_GIT
export MOCK_REMOTE_HEAD=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee

cat >"$TMP/mock-bin/hyprctl" <<'MOCK_HYPR'
#!/usr/bin/env bash
set -euo pipefail
if [[ $* == 'monitors -j' ]]; then
  printf '%s\n' '[{"focused":true,"name":"fixture","width":1920,"height":1080,"scale":1,"transform":0}]'
elif [[ $* == '-j getoption general:gaps_out' ]]; then
  printf '%s\n' '{"custom":"10"}'
elif [[ ${1:-} == eval ]]; then
  printf 'eval %s\n' "${2:-}" >>"$MOCK_LOG"
  printf 'ok\n'
else
  exit 1
fi
MOCK_HYPR
chmod 755 "$TMP/mock-bin/hyprctl"

cat >"$TMP/mock-bin/omarchy" <<'MOCK_OMARCHY'
#!/usr/bin/env bash
set -euo pipefail
if [[ $* == 'plugin list --json' ]]; then
  cat -- "$MOCK_PLUGIN_STATES"
  exit 0
fi
printf 'omarchy %s\n' "$*" >>"$MOCK_LOG"
if [[ -n ${MOCK_ACTION_SLEEP:-} ]]; then sleep "$MOCK_ACTION_SLEEP"; fi
if [[ ${1:-} == plugin && ( ${2:-} == enable || ${2:-} == disable ) ]]; then
  id=${3:-}
  [[ -n $id ]] || exit 2
  jq -e --arg id "$id" 'any(.[]; .id == $id)' "$MOCK_PLUGIN_STATES" \
    >/dev/null || exit 1
  next=$(mktemp "${MOCK_PLUGIN_STATES}.XXXXXX")
  jq --arg id "$id" --argjson enabled \
    "$([[ ${2:-} == enable ]] && printf true || printf false)" '
      map(if .id == $id then .enabled=$enabled else . end)
    ' "$MOCK_PLUGIN_STATES" >"$next"
  mv -fT -- "$next" "$MOCK_PLUGIN_STATES"
fi
exit 0
MOCK_OMARCHY
chmod 755 "$TMP/mock-bin/omarchy"

cat >"$TMP/mock-bin/omarchy-shell" <<'MOCK_SHELL'
#!/usr/bin/env bash
set -euo pipefail
printf 'shell %s\n' "$*" >>"$MOCK_LOG"
if [[ $* == 'shell summon b.okomart' ]]; then printf 'ok\n'
elif [[ $* == 'shell call b.okomart runtimeVersion ' ]]; then
  printf '%s\n' "${MOCK_RUNTIME_VERSION:-0.0.58}"
else
  exit 1
fi
MOCK_SHELL
chmod 755 "$TMP/mock-bin/omarchy-shell"

cat >"$TMP/mock-bin/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -euo pipefail
output=""
previous=""
for argument in "$@"; do
  if [[ $previous == --output ]]; then output=$argument; fi
  previous=$argument
done
url=${!#}
[[ -n $output ]] || exit 2
printf '%s\n' "$url" >>"$MOCK_LOG"

increment() {
  exec 9>>"$MOCK_COUNTER.lock"
  flock 9
  current=$(<"$MOCK_COUNTER")
  current=$((current + 1))
  printf '%s\n' "$current" >"$MOCK_COUNTER"
  maximum=$(<"$MOCK_MAX_COUNTER")
  if (( current > maximum )); then printf '%s\n' "$current" >"$MOCK_MAX_COUNTER"; fi
  flock -u 9
  exec 9>&-
}
decrement() {
  exec 9>>"$MOCK_COUNTER.lock"
  flock 9
  current=$(<"$MOCK_COUNTER")
  printf '%s\n' "$((current - 1))" >"$MOCK_COUNTER"
  flock -u 9
  exec 9>&-
}

case "$url" in
  *omarchy-plugin-marketplace*/registry.json)
    [[ ${MOCK_FAIL_REGISTRY:-0} != 1 ]] || exit 22
    cp -- "$MOCK_DATA/marketplace.json" "$output"
    ;;
  */HEAD/manifest.json)
    [[ ${MOCK_FAIL_MANIFESTS:-0} != 1 ]] || exit 22
    repository=$(sed -E 's#^.*/([^/]+)/HEAD/manifest\.json$#\1#' <<<"$url")
    [[ ${MOCK_FAIL_REPOSITORY:-} != "$repository" ]] || exit 22
    increment
    sleep "$MOCK_CURL_DELAY"
    cp -- "$MOCK_DATA/manifests/$repository.json" "$output"
    decrement
    ;;
  */commits\?path=manifest.json\&per_page=1)
    repository=$(sed -E 's#^.*/repos/[^/]+/([^/]+)/commits\?.*$#\1#' <<<"$url")
    increment
    sleep "$MOCK_CURL_DELAY"
    cp -- "$MOCK_DATA/commits/$repository.json" "$output"
    decrement
    ;;
  */git/trees/*\?recursive=1)
    repository=$(sed -E 's#^.*/repos/[^/]+/([^/]+)/git/trees/.*$#\1#' <<<"$url")
    cp -- "$MOCK_DATA/trees/$repository.json" "$output"
    ;;
  *) exit 22 ;;
esac
MOCK_CURL
chmod 755 "$TMP/mock-bin/curl"
export PATH="$TMP/mock-bin:$PATH"

"$OKOMART" prepare-window top 26 >"$TMP/window.json"
assert_jq "$TMP/window.json" '.ok and .prepared and .mode == "floating"
  and .width == 1044
  and .height == 1044 and .monitor == "fixture"' \
  'window preparation defaults to focused-monitor floating geometry'
grep -Fq 'float = true' "$MOCK_LOG" \
  || fail 'first-run window preparation did not request floating mode'
grep -Fq 'center = true' "$MOCK_LOG" \
  || fail 'floating window preparation did not center Okomart'

"$OKOMART" remember-window-mode tiled >"$TMP/remember-tiled.json"
assert_jq "$TMP/remember-tiled.json" '.ok and .mode == "tiled"' \
  'window mode accepts a tiled preference'
assert_jq "$XDG_STATE_HOME/okomart/window-mode.json" \
  '.schemaVersion == 1 and .mode == "tiled"' \
  'window mode persists under Okomart state'
[[ $(stat -c '%a' "$XDG_STATE_HOME/okomart/window-mode.json") == 600 ]] \
  || fail 'remembered window mode is not private'
pass 'remembered window mode is private'

: >"$MOCK_LOG"
"$OKOMART" prepare-window top 26 >"$TMP/tiled-window.json"
assert_jq "$TMP/tiled-window.json" '.ok and .prepared and .mode == "tiled"
  and .width == 1044 and .height == 1044' \
  'window preparation restores tiled mode'
grep -Fq 'float = false' "$MOCK_LOG" \
  || fail 'remembered tiled mode did not register a tiled window rule'
if grep -Fq 'center = true' "$MOCK_LOG" || grep -Fq 'size = {' "$MOCK_LOG"; then
  fail 'tiled window preparation retained floating-only placement rules'
fi
pass 'tiled window preparation omits floating-only placement rules'

if "$OKOMART" remember-window-mode maximized >"$TMP/invalid-window-mode.json"; then
  fail 'unsupported window mode was remembered'
fi
assert_jq "$TMP/invalid-window-mode.json" '.ok == false' \
  'unsupported window mode is rejected'
assert_jq "$XDG_STATE_HOME/okomart/window-mode.json" '.mode == "tiled"' \
  'invalid input leaves the remembered window mode unchanged'

printf '%s\n' '{"schemaVersion":1,"mode":"maximized"}' \
  >"$XDG_STATE_HOME/okomart/window-mode.json"
: >"$MOCK_LOG"
"$OKOMART" prepare-window top 26 >"$TMP/invalid-state-window.json"
assert_jq "$TMP/invalid-state-window.json" '.ok and .mode == "floating"' \
  'invalid persisted state falls back to floating'
grep -Fq 'float = true' "$MOCK_LOG" \
  || fail 'invalid persisted state did not register the floating fallback'

mkdir -p -- "$TMP/outside-window-state"
printf '%s\n' '{"schemaVersion":1,"mode":"tiled"}' \
  >"$TMP/outside-window-state/window-mode.json"
rm -f -- "$XDG_STATE_HOME/okomart/window-mode.json"
ln -s -- "$TMP/outside-window-state/window-mode.json" \
  "$XDG_STATE_HOME/okomart/window-mode.json"
: >"$MOCK_LOG"
"$OKOMART" prepare-window top 26 >"$TMP/symlink-state-window.json"
assert_jq "$TMP/symlink-state-window.json" '.ok and .mode == "floating"' \
  'symlinked persisted state falls back to floating'

"$OKOMART" remember-window-mode floating >"$TMP/remember-floating.json"
assert_jq "$TMP/remember-floating.json" '.ok and .mode == "floating"' \
  'window mode can return to floating'
[[ -f $XDG_STATE_HOME/okomart/window-mode.json \
  && ! -L $XDG_STATE_HOME/okomart/window-mode.json ]] \
  || fail 'window-mode write did not replace the state symlink itself'
assert_jq "$TMP/outside-window-state/window-mode.json" '.mode == "tiled"' \
  'window-mode writes never follow a state symlink'
: >"$MOCK_LOG"

SOURCE="$TMP/source"
mkdir -p -- "$SOURCE"
printf '%s\n' \
  'https://github.com/example/alpha.git' \
  'https://github.com/example/beta.git' \
  'https://git.example.com/catalog/generic.git' >"$SOURCE/plugins.txt"

manifest() {
  local repository=$1 id=$2 name=$3 version=$4 description=${5:-"$3 plugin"}
  jq -n --arg id "$id" --arg name "$name" --arg version "$version" \
    --arg description "$description" '{schemaVersion:1,id:$id,name:$name,
      version:$version,author:"Test",description:$description,license:"MIT",
      kinds:["panel"],entryPoints:{panel:"Main.qml"}}' \
    >"$MOCK_DATA/manifests/$repository.json"
}
commit_feed() {
  local repository=$1 revision=$2 timestamp=$3
  jq -n --arg revision "$revision" --arg timestamp "$timestamp" \
    '[{sha:$revision,commit:{committer:{date:$timestamp}}}]' \
    >"$MOCK_DATA/commits/$repository.json"
}

# Keep each manifest well below its supported size limit while making their
# combined catalog metadata larger than Linux's per-argument limit. Catalog
# assembly must read arrays from files instead of passing them through argv.
printf -v LARGE_DESCRIPTION '%*s' 45000 ''
LARGE_DESCRIPTION=${LARGE_DESCRIPTION// /x}
manifest alpha b.alpha Alpha 1.0.0 "$LARGE_DESCRIPTION"
manifest alpha-fork b.alpha 'Alpha marketplace alias' 9.0.0
manifest alpha-newer-alias b.alpha 'Newer alpha marketplace alias' 10.0.0
manifest beta b.beta Beta 1.0.0 "$LARGE_DESCRIPTION"
manifest gamma b.gamma Gamma 1.0.0 "$LARGE_DESCRIPTION"
ALPHA_REV=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BETA_REV=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
GAMMA_REV=cccccccccccccccccccccccccccccccccccccccc
BETA_VALIDATED_REV=6666666666666666666666666666666666666666
GAMMA_VALIDATED_REV=7777777777777777777777777777777777777777
BETA_VALIDATED_TIME=1740787200
GAMMA_VALIDATED_TIME=1743465600
commit_feed alpha "$ALPHA_REV" 2025-01-01T00:00:00Z
commit_feed beta "$BETA_REV" 2025-01-02T00:00:00Z
commit_feed gamma "$GAMMA_REV" 2025-01-03T00:00:00Z
jq -n '{sources:[
  {type:"plugin-source",repo:"https://github.com/example/alpha",plugins:{"b.alpha":{}}},
  {type:"plugin-source",repo:"https://github.com/example/beta",
    listingValidatedAt:"2025-03-01T00:00:00.000Z",
    listingValidatedCommit:"6666666666666666666666666666666666666666",
    plugins:{"b.beta":{}}},
  {type:"plugin-source",repo:"https://github.com/example/alpha-fork",plugins:{"b.alpha":{}}},
  {type:"plugin-source",repo:"https://github.com/example/alpha-newer-alias",plugins:{"b.alpha":{}}},
  {type:"plugin-source",repo:"https://github.com/example/gamma",
    listingValidatedAt:"2025-04-01T00:00:00.000Z",
    listingValidatedCommit:"7777777777777777777777777777777777777777",
    plugins:{"b.gamma":{}}},
  {type:"plugin-source",repo:"https://github.com/example/suite",plugins:{one:{},two:{}}},
  {type:"plugin-source",repo:"https://github.com/example/manual",plugins:{manual:{installation:{mode:"manual",note:"manual"}}}},
  {type:"plugin-source",repo:"https://github.com/example/okomart",plugins:{"b.okomart":{}}}
]}' >"$MOCK_DATA/marketplace.json"
# The live marketplace has outgrown the original one-megabyte download cap.
# Keep this valid JSON fixture above that boundary so a cold refresh cannot
# regress to rejecting the registry solely because of its current size.
printf -v MARKETPLACE_PADDING '%*s' $((1024 * 1024)) ''
printf '%s' "$MARKETPLACE_PADDING" >>"$MOCK_DATA/marketplace.json"
unset MARKETPLACE_PADDING
(( $(stat -c %s -- "$MOCK_DATA/marketplace.json") > 1024 * 1024 )) \
  || fail 'marketplace fixture did not exceed the former download cap'

# A snapshot is a disk-only read and creates no duplicate snapshot state.
"$OKOMART" snapshot "$SOURCE" >"$TMP/cold-local.json" || true
assert_jq "$TMP/cold-local.json" '.ok == false and .localOnly and .plugins == []' \
  'cold local snapshot returns immediately without an active catalog'
[[ ! -s $MOCK_LOG ]] || fail 'local-only snapshot accessed the network'
pass 'local-only snapshot performs no network work'
[[ -z $(find "$XDG_CACHE_HOME/okomart" -mindepth 1 -print -quit) ]] \
  || fail 'cold startup retained non-registry cache data'
[[ -f $TMP/outside-cache/sentinel ]] \
  || fail 'startup cache cleanup followed an out-of-root symlink target'
pass 'cold startup deletes every cache entry when no registry is present'
[[ ! -e $XDG_STATE_HOME/okomart/snapshot.json ]] || fail 'snapshot duplicate was persisted'
pass 'local-only snapshot does not persist a duplicate snapshot'

# Legacy data is removed only at the exact old cache/state targets.
mkdir -p -- "$TMP/outside-legacy" "$XDG_CACHE_HOME/okomart" \
  "$XDG_CACHE_HOME/okomart/registry.git" \
  "$XDG_CACHE_HOME/okomart/repositories"
printf 'keep\n' >"$TMP/outside-legacy/sentinel"
ln -s -- "$TMP/outside-legacy" "$XDG_CACHE_HOME/okomart/catalog"
printf '{}\n' >"$XDG_STATE_HOME/okomart/catalog.json"
printf '{}\n' >"$XDG_STATE_HOME/okomart/snapshot.json"
CATALOG="$XDG_CACHE_HOME/okomart/catalog.json"
PROGRESS_EVENTS="$TMP/refresh-progress.jsonl"
: >"$PROGRESS_EVENTS"
export OKOMART_GITHUB_MANIFEST_WORKERS=2
export OKOMART_GENERIC_MANIFEST_WORKERS=1
"$OKOMART" refresh "$SOURCE" --progress |
  while IFS= read -r event; do
    printf '%s\n' "$event" >>"$PROGRESS_EVENTS"
    if jq -e '.progress == true and .coldPublished == true' \
        <<<"$event" >/dev/null; then
      progress_wave=$(jq -r '.wave' <<<"$event")
      cp -- "$CATALOG" "$TMP/cold-wave-$progress_wave.json"
      if [[ $progress_wave == 1 ]]; then
        timeout 1s "$OKOMART" snapshot "$SOURCE" \
          >"$TMP/cold-wave-snapshot.json"
      fi
    fi
  done
unset OKOMART_GITHUB_MANIFEST_WORKERS OKOMART_GENERIC_MANIFEST_WORKERS
tail -n 1 "$PROGRESS_EVENTS" >"$TMP/refresh-cold.json"
jq -s '.' "$PROGRESS_EVENTS" >"$TMP/refresh-progress.json"
assert_jq "$TMP/refresh-progress.json" 'length == 4
  and ([.[0:3][].wave] == [1,2,3])
  and ([.[0:3][].completed] == [3,5,6])
  and ([.[0:3][].entryCount] == [3,4,4])
  and (.[3].progress != true)' \
  'cold refresh emits one render event after every completed request wave'
assert_jq "$TMP/cold-wave-1.json" '.active.partial == true
  and .active.completed == 3 and .active.total == 6
  and ([.active.entries[].id] | index("b.gamma") == null)' \
  'first request wave atomically publishes its accumulated plugin list'
assert_jq "$TMP/cold-wave-snapshot.json" '.ok and (.plugins | length) >= 3' \
  'progressive snapshot reads do not wait for the refresh writer lock'
assert_jq "$TMP/cold-wave-2.json" '.active.partial == true
  and .active.completed == 5
  and ([.active.entries[].id] | index("b.gamma") != null)' \
  'HANCORE sources are processed newest-first from the reversed registry'
assert_jq "$TMP/refresh-cold.json" '.ok and .coldPublished and .changed
  and .pending.ready == false' 'cold refresh publishes manifests before enrichment'
pass 'cold refresh accepts a valid marketplace larger than one megabyte'
for legacy in catalog registry.git repositories; do
  [[ ! -e $XDG_CACHE_HOME/okomart/$legacy ]] || fail "legacy $legacy survived cleanup"
done
[[ ! -e $XDG_STATE_HOME/okomart/catalog.json && ! -e $XDG_STATE_HOME/okomart/snapshot.json ]] \
  || fail 'legacy state duplicates survived cleanup'
pass 'legacy mirrors, materializations, and duplicate state are removed'
[[ -f $TMP/outside-legacy/sentinel ]] || fail 'legacy symlink cleanup followed its target'
pass 'legacy cleanup never follows an out-of-root symlink target'

assert_jq "$CATALOG" '
  .schemaVersion == 1 and (.active.entries|length) == 4
  and .pending.ready == false
  and all(.active.entries[]; has("images")|not)
  and ([.active.entries[].sourceUrl]|unique|length) == 4
  and .active.entries[0].id == "b.gamma"
  and .active.entries[1].id == "b.beta"
  and ([.active.entries[] | select(.id=="b.beta")][0].listingValidatedAt == '"$BETA_VALIDATED_TIME"')
  and ([.active.entries[] | select(.id=="b.gamma")][0].listingValidatedAt == '"$GAMMA_VALIDATED_TIME"')
  and (.pending.timestampSources
    | index("https://github.com/example/beta.git") == null)
  and (.pending.timestampSources
    | index("https://github.com/example/gamma.git") == null)' \
  'single catalog file merges local and compatible marketplace URLs'
(( $(jq -c '.active.entries' "$CATALOG" | wc -c) > 131072 )) \
  || fail 'large-catalog fixture did not exceed the Linux per-argument limit'
pass 'large catalog assembly is independent of process argument limits'
catalog_generation=$(jq -r '.active.generation' "$CATALOG")
mkdir -p -- "$XDG_CACHE_HOME/okomart/leftover-directory"
printf 'stale\n' >"$XDG_CACHE_HOME/okomart/leftover-file"
"$OKOMART" snapshot "$SOURCE" >"$TMP/startup-clean.json"
assert_eq "$catalog_generation" \
  "$(jq -r '.activeGeneration' "$TMP/startup-clean.json")" \
  'warm startup preserves the registry while removing other cache data'
mapfile -t cache_entries < <(
  find "$XDG_CACHE_HOME/okomart" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
)
[[ ${#cache_entries[@]} -eq 1 && ${cache_entries[0]} == catalog.json ]] \
  || fail "warm startup left unexpected cache entries: ${cache_entries[*]}"
pass 'catalog.json is the only persistent cache entry after startup'
assert_eq 1 "$(grep -Fc 'alpha/HEAD/manifest.json' "$MOCK_LOG")" \
  'local URL wins over the normalized marketplace duplicate'
assert_jq "$CATALOG" '
  any(.active.entries[];
    .id == "b.alpha"
    and .sourceUrl == "https://github.com/example/alpha.git")
  and all(.active.errors[];
    .sourceUrl != "https://github.com/example/alpha-fork.git")' \
  'local plugin id wins over a marketplace alias without a catalog error'
[[ -z $(grep -E '^clone https://github\.com/' "$MOCK_GIT_LOG" || true) ]] \
  || fail 'GitHub catalog metadata used git clone'
pass 'GitHub manifest metadata never uses git clone'
assert_eq 1 "$(grep -Fc 'clone https://git.example.com/catalog/generic.git' "$MOCK_GIT_LOG")" \
  'generic host uses one temporary partial clone'
[[ -z $(find "$XDG_RUNTIME_DIR/okomart-work" -maxdepth 1 \
  \( -name 'refresh.*' -o -name 'manifest-fetch.*' \) -print 2>/dev/null) ]] \
  || fail 'temporary manifest repository survived refresh'
pass 'generic manifest repository is deleted immediately'
(( $(<"$MOCK_MAX_COUNTER") >= 2 )) || fail 'manifest requests did not overlap'
pass 'manifest requests run concurrently'

GENERATION=$(jq -r '.pending.generation' "$CATALOG")
"$OKOMART" snapshot "$SOURCE" >"$TMP/cold-active.json"
assert_jq "$TMP/cold-active.json" '.ok and .localOnly and (.plugins|length) == 4
  and .pending.ready == false' 'cold active generation is browsable before timestamp work'
before_calls=$(wc -l <"$MOCK_LOG")
"$OKOMART" snapshot "$SOURCE" >/dev/null
assert_eq "$before_calls" "$(wc -l <"$MOCK_LOG")" 'warm cached startup remains local-only'

"$OKOMART" enrich "$GENERATION" >"$TMP/enriched.json"
assert_jq "$TMP/enriched.json" '.ok and .ready and (.enrichmentErrorCount == 0)' \
  'timestamp enrichment marks the exact pending generation ready'
assert_jq "$CATALOG" '.pending.ready
  and ([.pending.entries[] | select(.id=="b.alpha")][0].updatedAt == 1735689600)
  and ([.pending.entries[] | select(.id=="b.generic")][0].updatedAt == '"$GENERIC_TIME"')
  and ([.pending.entries[] | select(.id=="b.generic")][0].revision == "'"$GENERIC_HEAD"'")' \
  'GitHub manifest dates and generic HEAD dates are selected separately'
assert_jq "$CATALOG" '.pending.ready
  and ([.pending.entries[] | select(.id=="b.beta")][0]
    | .listingValidatedAt == '"$BETA_VALIDATED_TIME"'
      and .updatedAt == null and .revision == "'"$BETA_VALIDATED_REV"'")
  and ([.pending.entries[] | select(.id=="b.gamma")][0]
    | .listingValidatedAt == '"$GAMMA_VALIDATED_TIME"'
      and .updatedAt == null and .revision == "'"$GAMMA_VALIDATED_REV"'")' \
  'validated dates order marketplace entries without last-update lookups'
[[ -z $(grep -F '/repos/example/beta/commits?path=manifest.json&per_page=1' \
  "$MOCK_LOG" || true) ]] \
  || fail 'local URL with marketplace validation metadata requested a last-update timestamp'
[[ -z $(grep -F '/repos/example/gamma/commits?path=manifest.json&per_page=1' \
  "$MOCK_LOG" || true) ]] \
  || fail 'marketplace URL with validation metadata requested a last-update timestamp'
pass 'validated marketplace entries skip last-update timestamp requests'

if "$OKOMART" promote dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd \
    >"$TMP/stale-promote.json"; then fail 'stale generation promotion succeeded'; fi
assert_jq "$TMP/stale-promote.json" '.stale and (.promoted|not)' \
  'promotion rejects a stale generation token'
"$OKOMART" promote "$GENERATION" >"$TMP/promoted.json"
assert_jq "$TMP/promoted.json" '.ok and .promoted and .generation == "'"$GENERATION"'"' \
  'ready generation promotes atomically'
assert_jq "$CATALOG" '.active.generation == "'"$GENERATION"'" and .pending == null' \
  'promotion swaps active and clears pending in one file'
if "$OKOMART" action "$SOURCE" install b.alpha \
    dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd \
    >"$TMP/stale-action.json"; then
  fail 'action accepted a stale active generation'
fi
assert_jq "$TMP/stale-action.json" '.staleConfirmation and (.started|not)' \
  'actions reject stale active-generation confirmation tokens'

jq -n '{ok:true,running:true,action:"install",actionId:"abandoned",
  pid:999999,startedAt:"",finishedAt:"",message:"Working",results:[],
  acknowledged:false}' >"$XDG_STATE_HOME/okomart/action.json"
"$OKOMART" status >"$TMP/abandoned-action.json"
assert_jq "$TMP/abandoned-action.json" '.running == false and .abandoned
  and .results[0].id == "worker" and .acknowledged == false' \
  'action status reconciles an abandoned detached worker'
rm -f -- "$XDG_STATE_HOME/okomart/action.json"

cp -- "$ROOT/manifest.json" "$SOURCE/manifest.json"
export MOCK_RUNTIME_VERSION
MOCK_RUNTIME_VERSION=$(jq -r '.version' "$ROOT/manifest.json")
: >"$MOCK_LOG"
if ! run_action_to_completion "$SOURCE" install b.alpha "$GENERATION" \
    >"$TMP/action-install.json"; then
  cat -- "$TMP/action-install.json" >&2
  cat -- "$XDG_STATE_HOME/okomart/action.log" >&2 2>/dev/null || true
  fail 'exact-generation install action failed'
fi
assert_jq "$TMP/action-install.json" '.ok and (.running|not)
  and any(.results[]; .id=="b.alpha" and .operation=="install" and .ok)
  and .shellRestarted and .runtimeReloaded and .resummoned' \
  'exact-generation install action completes through the detached worker'
grep -Fqx 'omarchy plugin add https://github.com/example/alpha.git --enable --yes' \
  "$MOCK_LOG" || fail 'install action did not use the confirmed catalog URL'
pass 'install action uses the authoritative add-and-enable command'
grep -Fqx 'omarchy restart shell' "$MOCK_LOG" \
  || fail 'successful install did not restart the shell once'
pass 'successful install retains clean runtime reload behavior'
ACTION_ID=$(jq -r '.actionId' "$TMP/action-install.json")
"$OKOMART" ack "$ACTION_ID" >"$TMP/action-ack.json"
assert_jq "$TMP/action-ack.json" '.ok and .acknowledged' \
  'completed detached actions remain explicitly acknowledgeable'
unset MOCK_RUNTIME_VERSION

# An unchanged refresh updates check state without showing a pending catalog.
"$OKOMART" refresh "$SOURCE" >"$TMP/unchanged.json"
assert_jq "$TMP/unchanged.json" '.ok and (.changed|not) and .pending == null' \
  'unchanged warm refresh clears refresh state'
assert_jq "$CATALOG" '.pending == null
  and ([.active.entries[] | select(.id=="b.alpha")][0].updatedAt == 1735689600)' \
  'equal versions preserve the selected timestamp'

# A manifest version change does not seek a last-update timestamp when the
# registry already supplies a validation time.
manifest beta b.beta Beta 1.1.0 'Beta validated upgrade'
: >"$MOCK_LOG"
"$OKOMART" refresh "$SOURCE" >"$TMP/validated-upgrade.json"
assert_jq "$CATALOG" '.pending.ready == true
  and .pending.timestampSources == []
  and ([.pending.entries[] | select(.id=="b.beta")][0]
    | .version == "1.1.0"
      and .listingValidatedAt == '"$BETA_VALIDATED_TIME"'
      and .updatedAt == null
      and .revision == "'"$BETA_VALIDATED_REV"'")' \
  'validated version upgrade stages without a last-update lookup'
[[ -z $(grep -F '/repos/example/beta/commits?path=manifest.json&per_page=1' \
  "$MOCK_LOG" || true) ]] \
  || fail 'validated version upgrade requested a last-update timestamp'
pass 'validated version upgrades never seek last-update timestamps'
VALIDATED_UPGRADE_GENERATION=$(jq -r '.pending.generation' "$CATALOG")
"$OKOMART" promote "$VALIDATED_UPGRADE_GENERATION" >/dev/null

# Only strict SemVer precedence requests a replacement timestamp.
semver_case() {
  local available=$1 previous=$2 expected=$3
  "$OKOMART" _semver-higher "$available" "$previous" >"$TMP/semver.json"
  assert_jq "$TMP/semver.json" ".higher == $expected" \
    "SemVer precedence: $available compared with $previous"
}
semver_case 1.0.1 1.0.0 true
semver_case 1.0.0 1.0.0 false
semver_case 1.0.0 1.0.0-rc.9 true
semver_case 1.0.0-rc.2 1.0.0-rc.10 false
semver_case 1.0.0+build.2 1.0.0+build.1 false
semver_case invalid 1.0.0 false
semver_case 1.0.0 invalid false

manifest alpha b.alpha Alpha 1.1.0 'Alpha upgraded'
commit_feed alpha dddddddddddddddddddddddddddddddddddddddd 2025-02-01T00:00:00Z
"$OKOMART" refresh "$SOURCE" >"$TMP/upgrade.json"
assert_jq "$CATALOG" '.pending.ready == false
  and ([.pending.entries[] | select(.id=="b.alpha")][0].updatedAt == 1735689600)
  and (.pending.timestampSources | index("https://github.com/example/alpha.git") != null)' \
  'strict version upgrade preserves the old date until enrichment finishes'
UPGRADE_GENERATION=$(jq -r '.pending.generation' "$CATALOG")
"$OKOMART" enrich "$UPGRADE_GENERATION" >/dev/null
assert_jq "$CATALOG" '([.pending.entries[] | select(.id=="b.alpha")][0].updatedAt == 1738368000)' \
  'version upgrade advances to the manifest-changing commit date'
"$OKOMART" promote "$UPGRADE_GENERATION" >/dev/null

manifest alpha b.alpha Alpha 1.1.0 'Metadata changed at equal version'
"$OKOMART" refresh "$SOURCE" >/dev/null
assert_jq "$CATALOG" '.pending.ready == true
  and ([.pending.entries[] | select(.id=="b.alpha")][0].updatedAt == 1738368000)' \
  'equal-version metadata change stages immediately with its prior timestamp'
EQUAL_GENERATION=$(jq -r '.pending.generation' "$CATALOG")
"$OKOMART" promote "$EQUAL_GENERATION" >/dev/null

manifest alpha b.alpha Alpha not-semver 'Invalid version metadata'
"$OKOMART" refresh "$SOURCE" >/dev/null
assert_jq "$CATALOG" '.pending.ready == true
  and ([.pending.entries[] | select(.id=="b.alpha")][0].updatedAt == 1738368000)' \
  'invalid versions remain displayable without advancing timestamps'

# Per-entry failures are recorded and omitted; registry failure preserves active.
export MOCK_FAIL_REPOSITORY=beta
"$OKOMART" refresh "$SOURCE" >"$TMP/partial.json"
unset MOCK_FAIL_REPOSITORY
assert_jq "$TMP/partial.json" '.ok and .changed' 'individual manifest failure does not abort the candidate'
assert_jq "$CATALOG" '([.pending.entries[].id] | index("b.beta") == null)
  and any(.pending.errors[]; .sourceUrl == "https://github.com/example/beta.git")' \
  'failed plugin is omitted with a catalog error'
ACTIVE_BEFORE=$(jq -r '.active.generation' "$CATALOG")
export MOCK_FAIL_REGISTRY=1
if "$OKOMART" refresh "$SOURCE" >"$TMP/registry-failure.json"; then
  fail 'registry-level failure unexpectedly succeeded'
fi
unset MOCK_FAIL_REGISTRY
assert_eq "$ACTIVE_BEFORE" "$(jq -r '.active.generation' "$CATALOG")" \
  'registry-source failure preserves active generation'

FAIL_SOURCE="$TMP/fail-source"
mkdir -p -- "$FAIL_SOURCE"
printf '%s\n' 'https://github.com/example/alpha.git' >"$FAIL_SOURCE/plugins.txt"
export MOCK_FAIL_MANIFESTS=1
if "$OKOMART" refresh "$FAIL_SOURCE" >"$TMP/all-failed.json"; then
  fail 'all-plugin request failure unexpectedly published a candidate'
fi
unset MOCK_FAIL_MANIFESTS
assert_jq "$TMP/all-failed.json" '.ok == false and (.error|contains("Every plugin"))' \
  'all-plugin request failure rejects the candidate'
assert_eq "$ACTIVE_BEFORE" "$(jq -r '.active.generation' "$CATALOG")" \
  'all-plugin request failure preserves active generation'

export MOCK_CURL_DELAY=2
export OKOMART_REFRESH_DEADLINE_SECONDS=1
if "$OKOMART" refresh "$SOURCE" >"$TMP/timeout.json"; then
  fail 'overall refresh timeout unexpectedly succeeded'
fi
unset OKOMART_REFRESH_DEADLINE_SECONDS
export MOCK_CURL_DELAY=0.08
assert_jq "$TMP/timeout.json" '.ok == false and (.error|contains("overall time limit"))' \
  'overall refresh timeout rejects the candidate'
assert_eq "$ACTIVE_BEFORE" "$(jq -r '.active.generation' "$CATALOG")" \
  'overall refresh timeout preserves active generation'
[[ -z $(find "$XDG_RUNTIME_DIR/okomart-work" -maxdepth 1 \
  -name 'refresh.*' -print -quit 2>/dev/null) ]] \
  || fail 'timed-out refresh left working data behind'
pass 'timed-out refresh cleans temporary repositories'

# Timestamp failure is non-blocking and retains an existing timestamp.
rm -f -- "$MOCK_DATA/commits/alpha.json"
manifest alpha b.alpha Alpha 2.0.0 'Timestamp lookup fails'
"$OKOMART" refresh "$SOURCE" >/dev/null
FAILED_TIME_GENERATION=$(jq -r '.pending.generation' "$CATALOG")
"$OKOMART" enrich "$FAILED_TIME_GENERATION" >"$TMP/time-failure.json"
assert_jq "$TMP/time-failure.json" '.ok and .ready and .enrichmentErrorCount >= 1' \
  'timestamp failure does not block readiness'
assert_jq "$CATALOG" '([.pending.entries[] | select(.id=="b.alpha")][0].updatedAt == 1738368000)
  and any(.pending.errors[]; .phase == "timestamp")' \
  'timestamp failure preserves the existing selected date and records an error'

# Lazy GitHub screenshot discovery uses one revision-pinned tree lookup.
jq -n '{tree:[
  {path:"preview.png",type:"blob",mode:"100644"},
  {path:"images/second.webp",type:"blob",mode:"100644"},
  {path:"screenshots/third.JPG",type:"blob",mode:"100755"},
  {path:"images/nested/no.png",type:"blob",mode:"100644"},
  {path:"docs/readme.png",type:"blob",mode:"100644"},
  {path:"images/link.png",type:"blob",mode:"120000"}
]}' >"$MOCK_DATA/trees/alpha.json"
"$OKOMART" screenshots "$(jq -cn --arg revision "$ALPHA_REV" '{id:"b.alpha",
  sourceUrl:"https://github.com/example/alpha.git",revision:$revision,installedPath:""}')" \
  media-alpha >"$TMP/github-images.json"
assert_jq "$TMP/github-images.json" '.ok and (.images|length) == 3
  and all(.images[]; contains("/'"$ALPHA_REV"'/"))
  and (any(.images[]; endswith("preview.png")))' \
  'GitHub screenshots are discovered lazily from supported locations at the selected revision'

"$OKOMART" screenshots "$(jq -cn --arg revision "$GENERIC_HEAD" '{id:"b.generic",
  sourceUrl:"https://git.example.com/catalog/generic.git",revision:$revision,installedPath:""}')" \
  media-generic >"$TMP/generic-images.json"
assert_jq "$TMP/generic-images.json" '.ok and (.images|length) == 1
  and .revision == "'"$GENERIC_HEAD"'"' \
  'generic-host screenshots use the current private runtime repository'
GENERIC_IMAGE=$(jq -r '.images[0]' "$TMP/generic-images.json")
[[ -f $GENERIC_IMAGE ]] || fail 'generic screenshot was not materialized'
pass 'generic screenshot blob is materialized only in the runtime session'
"$OKOMART" cleanup-media media-generic >/dev/null
[[ ! -e $XDG_RUNTIME_DIR/okomart/session-media-generic ]] \
  || fail 'generic runtime repository survived selection cleanup'
pass 'generic screenshot repository is removed on selection cleanup'

LOCAL_PLUGIN="$HOME/.config/omarchy/plugins/b.local"
mkdir -p -- "$LOCAL_PLUGIN/screenshots"
printf 'local qml\n' >"$LOCAL_PLUGIN/Local.qml"
printf 'local screenshot\n' >"$LOCAL_PLUGIN/screenshots/local.png"
jq -n '{schemaVersion:1,id:"b.local",name:"Local",version:"1.0.0",
  author:"Test",description:"Installed local plugin",kinds:["panel"],
  entryPoints:{panel:"Local.qml"}}' >"$LOCAL_PLUGIN/manifest.json"
jq -n '[{id:"b.local",enabled:true,canDisable:true}]' >"$MOCK_PLUGIN_STATES"
"$OKOMART" snapshot "$SOURCE" >"$TMP/installed-local.json"
assert_jq "$TMP/installed-local.json" '([.plugins[] | select(.id=="b.local")][0]
  | .installed and .enabled and .canDisable and (has("images")|not))' \
  'installed snapshots include authoritative enabled state without screenshot paths'

ENABLEMENT_GENERATION=$(jq -r '.active.generation' "$CATALOG")
export MOCK_RUNTIME_VERSION
MOCK_RUNTIME_VERSION=$(jq -r '.version' "$ROOT/manifest.json")
: >"$MOCK_LOG"
run_action_to_completion "$SOURCE" disable b.local "$ENABLEMENT_GENERATION" \
  >"$TMP/action-disable.json"
assert_jq "$TMP/action-disable.json" '.ok and (.running|not)
  and any(.results[]; .id=="b.local" and .operation=="disable" and .ok)' \
  'installed plugin can be disabled through the detached action worker'
grep -Fqx 'omarchy plugin disable b.local' "$MOCK_LOG" \
  || fail 'disable action did not use the public Omarchy plugin command'
if grep -Fqx 'omarchy restart shell' "$MOCK_LOG"; then
  fail 'disable action restarted the shell instead of using the live mutation'
fi
"$OKOMART" snapshot "$SOURCE" >"$TMP/disabled-local.json"
assert_jq "$TMP/disabled-local.json" '([.plugins[] | select(.id=="b.local")][0]
  | .installed and .enabled == false and .canDisable)' \
  'disabled state is reflected in the next local snapshot'

: >"$MOCK_LOG"
run_action_to_completion "$SOURCE" enable b.local "$ENABLEMENT_GENERATION" \
  >"$TMP/action-enable.json"
assert_jq "$TMP/action-enable.json" '.ok and (.running|not)
  and any(.results[]; .id=="b.local" and .operation=="enable" and .ok)' \
  'disabled plugin can be enabled through the detached action worker'
grep -Fqx 'omarchy plugin enable b.local' "$MOCK_LOG" \
  || fail 'enable action did not use the public Omarchy plugin command'
"$OKOMART" snapshot "$SOURCE" >"$TMP/enabled-local.json"
assert_jq "$TMP/enabled-local.json" '([.plugins[] | select(.id=="b.local")][0]
  | .installed and .enabled and .canDisable)' \
  'enabled state is reflected in the next local snapshot'

jq 'map(if .id == "b.local" then .canDisable=false else . end)' \
  "$MOCK_PLUGIN_STATES" >"$TMP/non-disableable-state.json"
mv -fT -- "$TMP/non-disableable-state.json" "$MOCK_PLUGIN_STATES"
: >"$MOCK_LOG"
if run_action_to_completion "$SOURCE" disable b.local "$ENABLEMENT_GENERATION" \
    >"$TMP/action-disable-blocked.json"; then
  fail 'full-bar-style plugin unexpectedly allowed a direct disable action'
fi
assert_jq "$TMP/action-disable-blocked.json" '.ok == false and (.running|not)
  and any(.results[]; .id=="b.local" and .operation=="disable"
    and (.ok|not) and (.output|contains("enable a replacement bar")))' \
  'plugins marked non-disableable are rejected before mutation'
if grep -Fqx 'omarchy plugin disable b.local' "$MOCK_LOG"; then
  fail 'blocked disable action still invoked the public Omarchy command'
fi
pass 'blocked disable action does not invoke Omarchy mutation'
unset MOCK_RUNTIME_VERSION
CATALOG_HASH_BEFORE=$(sha256sum "$CATALOG" | awk '{print $1}')
"$OKOMART" check-updates "$SOURCE" >"$TMP/update-check.json"
assert_jq "$TMP/update-check.json" '.ok and .remoteChecked
  and .activeGeneration == "'"$(jq -r '.active.generation' "$CATALOG")"'"' \
  'installed and self update status is checked independently'
assert_eq "$CATALOG_HASH_BEFORE" "$(sha256sum "$CATALOG" | awk '{print $1}')" \
  'session update checks do not write catalog metadata'
"$OKOMART" screenshots "$(jq -cn --arg path "$(realpath -m -- "$LOCAL_PLUGIN")" \
  '{id:"b.local",sourceUrl:"",revision:"",installedPath:$path}')" \
  media-local >"$TMP/local-images.json"
assert_jq "$TMP/local-images.json" '.ok and (.images|length) == 1
  and (.images[0]|endswith("/screenshots/local.png"))' \
  'installed screenshots use the same lazy discovery command'

mkdir -p -- "$XDG_RUNTIME_DIR/okomart/session-abandoned"
"$OKOMART" cleanup-media --all >/dev/null
[[ ! -e $XDG_RUNTIME_DIR/okomart ]] || fail 'abandoned runtime sessions survived launch cleanup'
pass 'abandoned screenshot sessions are cleaned on the next launch'

printf '1..%d\n' "$pass_count"
