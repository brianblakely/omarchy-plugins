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
export MOCK_CURL_DELAY=0.08
mkdir -p -- "$HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" \
  "$MOCK_DATA/manifests" "$MOCK_DATA/commits" "$MOCK_DATA/trees" "$TMP/mock-bin"
chmod 700 "$XDG_RUNTIME_DIR"
: >"$MOCK_LOG"; : >"$MOCK_GIT_LOG"; printf '0\n' >"$MOCK_COUNTER"; printf '0\n' >"$MOCK_MAX_COUNTER"

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
printf 'omarchy %s\n' "$*" >>"$MOCK_LOG"
if [[ -n ${MOCK_ACTION_SLEEP:-} ]]; then sleep "$MOCK_ACTION_SLEEP"; fi
exit 0
MOCK_OMARCHY
chmod 755 "$TMP/mock-bin/omarchy"

cat >"$TMP/mock-bin/omarchy-shell" <<'MOCK_SHELL'
#!/usr/bin/env bash
set -euo pipefail
printf 'shell %s\n' "$*" >>"$MOCK_LOG"
if [[ $* == 'shell summon b.okomart' ]]; then printf 'ok\n'
elif [[ $* == 'shell call b.okomart runtimeVersion ' ]]; then
  printf '%s\n' "${MOCK_RUNTIME_VERSION:-0.0.56}"
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
assert_jq "$TMP/window.json" '.ok and .prepared and .width == 1044
  and .height == 1044 and .monitor == "fixture"' \
  'window preparation still registers focused-monitor square geometry'
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

manifest alpha b.alpha Alpha 1.0.0
manifest beta b.beta Beta 1.0.0
manifest gamma b.gamma Gamma 1.0.0
ALPHA_REV=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BETA_REV=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
GAMMA_REV=cccccccccccccccccccccccccccccccccccccccc
commit_feed alpha "$ALPHA_REV" 2025-01-01T00:00:00Z
commit_feed beta "$BETA_REV" 2025-01-02T00:00:00Z
commit_feed gamma "$GAMMA_REV" 2025-01-03T00:00:00Z
jq -n '{sources:[
  {type:"plugin-source",repo:"https://github.com/example/alpha",plugins:{"b.alpha":{}}},
  {type:"plugin-source",repo:"https://github.com/example/gamma",plugins:{"b.gamma":{}}},
  {type:"plugin-source",repo:"https://github.com/example/suite",plugins:{one:{},two:{}}},
  {type:"plugin-source",repo:"https://github.com/example/manual",plugins:{manual:{installation:{mode:"manual",note:"manual"}}}},
  {type:"plugin-source",repo:"https://github.com/example/okomart",plugins:{"b.okomart":{}}}
]}' >"$MOCK_DATA/marketplace.json"

# A snapshot is a disk-only read and creates no duplicate snapshot state.
"$OKOMART" snapshot "$SOURCE" >"$TMP/cold-local.json" || true
assert_jq "$TMP/cold-local.json" '.ok == false and .localOnly and .plugins == []' \
  'cold local snapshot returns immediately without an active catalog'
[[ ! -s $MOCK_LOG ]] || fail 'local-only snapshot accessed the network'
pass 'local-only snapshot performs no network work'
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
"$OKOMART" refresh "$SOURCE" >"$TMP/refresh-cold.json"
assert_jq "$TMP/refresh-cold.json" '.ok and .coldPublished and .changed
  and .pending.ready == false' 'cold refresh publishes manifests before enrichment'
for legacy in catalog registry.git repositories; do
  [[ ! -e $XDG_CACHE_HOME/okomart/$legacy ]] || fail "legacy $legacy survived cleanup"
done
[[ ! -e $XDG_STATE_HOME/okomart/catalog.json && ! -e $XDG_STATE_HOME/okomart/snapshot.json ]] \
  || fail 'legacy state duplicates survived cleanup'
pass 'legacy mirrors, materializations, and duplicate state are removed'
[[ -f $TMP/outside-legacy/sentinel ]] || fail 'legacy symlink cleanup followed its target'
pass 'legacy cleanup never follows an out-of-root symlink target'

CATALOG="$XDG_CACHE_HOME/okomart/catalog.json"
assert_jq "$CATALOG" '.schemaVersion == 1 and (.active.entries|length) == 4
  and .pending.ready == false
  and all(.active.entries[]; has("images")|not)
  and ([.active.entries[].sourceUrl]|unique|length) == 4' \
  'single catalog file merges local and compatible marketplace URLs'
assert_eq 1 "$(grep -Fc 'alpha/HEAD/manifest.json' "$MOCK_LOG")" \
  'local URL wins over the normalized marketplace duplicate'
[[ -z $(grep -E '^clone https://github\.com/' "$MOCK_GIT_LOG" || true) ]] \
  || fail 'GitHub catalog metadata used git clone'
pass 'GitHub manifest metadata never uses git clone'
assert_eq 1 "$(grep -Fc 'clone https://git.example.com/catalog/generic.git' "$MOCK_GIT_LOG")" \
  'generic host uses one temporary partial clone'
[[ -z $(find "$XDG_CACHE_HOME/okomart" -maxdepth 1 -name '.refresh.*' -o -name '.manifest-fetch.*') ]] \
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
[[ -z $(find "$XDG_CACHE_HOME/okomart" -maxdepth 1 -name '.refresh.*' -print -quit) ]] \
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
"$OKOMART" snapshot "$SOURCE" >"$TMP/installed-local.json"
assert_jq "$TMP/installed-local.json" '([.plugins[] | select(.id=="b.local")][0]
  | .installed and (has("images")|not))' \
  'installed screenshot paths are omitted from local snapshots'
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
