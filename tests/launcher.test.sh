#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SERVICE="$ROOT_DIR/Service.qml"
ASSET="$ROOT_DIR/assets/b.okomart.desktop"
TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT

fail() {
  printf 'launcher.test.sh: %s\n' "$*" >&2
  exit 1
}

extract_script() {
  local property=$1 line
  line=$(sed -n "s/^  readonly property string ${property}: //p" "$SERVICE")
  [[ -n $line ]] || fail "could not find $property in Service.qml"
  printf '%s\n' "$line" | jq -Rr fromjson
}

run_script() {
  local script=$1 process_name=$2
  shift 2
  bash -c "$script" "$process_name" "$@"
}

command -v jq >/dev/null || fail "jq is required"
command -v desktop-file-validate >/dev/null || fail "desktop-file-validate is required"
command -v gio >/dev/null || fail "gio is required"

desktop-file-validate "$ASSET"
jq -e '
  .schemaVersion == 1
  and .id == "b.okomart"
  and .name == "Okomart"
  and .version == "0.0.82"
  and .author == "Brian Blakely"
  and .license == "MIT"
  and .kinds == ["service", "panel"]
  and .entryPoints == {"service":"Service.qml","panel":"Okomart.qml"}
  and (has("install") | not)
  and (has("hooks") | not)
  and (has("postInstall") | not)
' "$ROOT_DIR/manifest.json" >/dev/null

grep -Fq 'Quickshell.execDetached([' "$SERVICE" \
  || fail "cleanup must be detached so service destruction cannot cancel it"
grep -Fq 'Quickshell.execDetached([helperPath, "_recover-self-update", sourceDir])' \
  "$SERVICE" \
  || fail "service reload does not recover a completed Okomart self-update"
grep -Fq 'onHelperPathChanged: recoverSelfUpdate()' "$SERVICE" \
  || fail "self-update recovery does not wait for the injected manifest"
grep -Fq 'X-Okomart-Managed=true' "$ASSET" \
  || fail "desktop entry is missing its ownership marker"
grep -Fq 'omarchy-shell shell summon b.okomart' "$ASSET" \
  || fail "desktop entry does not summon Okomart"
grep -Fq '$HOME/.config/omarchy/plugins/b.okomart/manifest.json' "$ASSET" \
  || fail "desktop entry does not guard against an offline removal"

INSTALL_SCRIPT=$(extract_script installScript)
CLEANUP_SCRIPT=$(extract_script cleanupScript)
TARGET="$TEST_DIR/data/applications/b.okomart.desktop"
CONFIG="$TEST_DIR/config/omarchy/shell.json"

run_script "$INSTALL_SCRIPT" install "$ASSET" "$TARGET"
cmp -- "$ASSET" "$TARGET" || fail "installed desktop entry differs from its asset"
[[ $(stat -c '%a' "$TARGET") == 644 ]] || fail "desktop entry mode is not 0644"
[[ -z $(find "$(dirname -- "$TARGET")" -name 'b.okomart.desktop.tmp.*' -print -quit) ]] \
  || fail "atomic install left a temporary file behind"

printf '%s\n' 'locally changed' >> "$TARGET"
run_script "$INSTALL_SCRIPT" reinstall "$ASSET" "$TARGET"
cmp -- "$ASSET" "$TARGET" || fail "repeat install did not restore the managed entry"

mkdir -p -- "$(dirname -- "$CONFIG")"
printf '%s\n' '{"version":1,"plugins":[{"id":"b.okomart"}]}' > "$CONFIG"
run_script "$CLEANUP_SCRIPT" cleanup-enabled "$TARGET" "$CONFIG"
[[ -f $TARGET ]] || fail "cleanup removed the launcher while Okomart was enabled"

printf '%s\n' '{"version":1,"plugins":[{"id":"someone.else"}]}' > "$CONFIG"
run_script "$CLEANUP_SCRIPT" cleanup-disabled "$TARGET" "$CONFIG"
[[ ! -e $TARGET ]] || fail "cleanup retained the launcher after Okomart was disabled"

run_script "$INSTALL_SCRIPT" reinstall "$ASSET" "$TARGET"
printf '%s\n' '{ malformed' > "$CONFIG"
run_script "$CLEANUP_SCRIPT" cleanup-malformed "$TARGET" "$CONFIG"
[[ -f $TARGET ]] || fail "cleanup removed the launcher when config could not be verified"

printf '%s\n' '[Desktop Entry]' 'Name=User-owned Okomart' > "$TARGET"
printf '%s\n' '{"version":1,"plugins":[]}' > "$CONFIG"
run_script "$CLEANUP_SCRIPT" cleanup-unowned "$TARGET" "$CONFIG"
[[ -f $TARGET ]] || fail "cleanup removed a desktop entry without Okomart's marker"
if run_script "$INSTALL_SCRIPT" install-unowned "$ASSET" "$TARGET" 2>/dev/null; then
  fail "install replaced a desktop entry without Okomart's marker"
fi
grep -Fq 'Name=User-owned Okomart' "$TARGET" \
  || fail "refused install still changed the user-owned desktop entry"

rm -f -- "$TARGET"
SYMLINK_TARGET="$TEST_DIR/user-owned.desktop"
printf '%s\n' 'X-Okomart-Managed=true' >"$SYMLINK_TARGET"
ln -s -- "$SYMLINK_TARGET" "$TARGET"
if run_script "$INSTALL_SCRIPT" install-symlink "$ASSET" "$TARGET" 2>/dev/null; then
  fail "install replaced a symlink launcher"
fi
run_script "$CLEANUP_SCRIPT" cleanup-symlink "$TARGET" "$CONFIG"
[[ -L $TARGET && -f $SYMLINK_TARGET ]] \
  || fail "cleanup changed a symlink launcher or its target"
rm -f -- "$TARGET"

run_script "$INSTALL_SCRIPT" final-install "$ASSET" "$TARGET"
rm -f -- "$CONFIG"
run_script "$CLEANUP_SCRIPT" cleanup-missing-config "$TARGET" "$CONFIG"
[[ ! -e $TARGET ]] || fail "cleanup retained the managed launcher with no enabling config"

LAUNCH_HOME="$TEST_DIR/launch home [fixture]"
LAUNCH_DATA="$TEST_DIR/launch data [fixture]"
LAUNCH_TARGET="$LAUNCH_DATA/applications/b.okomart.desktop"
MOCK_BIN="$TEST_DIR/mock-bin"
LAUNCH_LOG="$TEST_DIR/launch.log"
mkdir -p -- "$LAUNCH_HOME/.config/omarchy/plugins/b.okomart" \
  "$LAUNCH_DATA/applications" "$MOCK_BIN"
printf '%s\n' '{}' >"$LAUNCH_HOME/.config/omarchy/plugins/b.okomart/manifest.json"
install -m 0644 -- "$ASSET" "$LAUNCH_TARGET"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >>"$OKOMART_LAUNCH_LOG"' \
  >"$MOCK_BIN/omarchy-shell"
chmod 0755 "$MOCK_BIN/omarchy-shell"

env HOME="$LAUNCH_HOME" XDG_DATA_HOME="$LAUNCH_DATA" \
  PATH="$MOCK_BIN:$PATH" OKOMART_LAUNCH_LOG="$LAUNCH_LOG" \
  gio launch "$LAUNCH_TARGET"
for _ in {1..40}; do
  [[ -s $LAUNCH_LOG ]] && break
  sleep 0.05
done
grep -Fqx 'shell summon b.okomart' "$LAUNCH_LOG" \
  || fail "launcher did not summon Okomart while its checkout existed"
[[ -f $LAUNCH_TARGET ]] \
  || fail "launcher removed itself while Okomart was still installed"

rm -f -- "$LAUNCH_HOME/.config/omarchy/plugins/b.okomart/manifest.json"
: >"$LAUNCH_LOG"
env HOME="$LAUNCH_HOME" XDG_DATA_HOME="$LAUNCH_DATA" \
  PATH="$MOCK_BIN:$PATH" OKOMART_LAUNCH_LOG="$LAUNCH_LOG" \
  gio launch "$LAUNCH_TARGET"
for _ in {1..40}; do
  [[ ! -e $LAUNCH_TARGET ]] && break
  sleep 0.05
done
[[ ! -e $LAUNCH_TARGET ]] \
  || fail "launcher left by an offline removal did not self-clean"
[[ ! -s $LAUNCH_LOG ]] \
  || fail "stale launcher contacted omarchy-shell after offline removal"

sed '/^X-Okomart-Managed=true$/d' "$ASSET" >"$LAUNCH_TARGET"
env HOME="$LAUNCH_HOME" XDG_DATA_HOME="$LAUNCH_DATA" \
  PATH="$MOCK_BIN:$PATH" OKOMART_LAUNCH_LOG="$LAUNCH_LOG" \
  gio launch "$LAUNCH_TARGET"
sleep 0.1
[[ -f $LAUNCH_TARGET ]] \
  || fail "stale launcher cleanup removed an unmarked desktop entry"
[[ ! -s $LAUNCH_LOG ]] \
  || fail "unmarked stale launcher contacted omarchy-shell"

printf 'launcher.test.sh: all checks passed\n'
