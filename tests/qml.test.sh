#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OMARCHY_SOURCE=""
RUNTIME_TMP=""

cleanup() {
  if [[ -n $RUNTIME_TMP && -d $RUNTIME_TMP ]]; then
    rm -rf -- "$RUNTIME_TMP"
  fi
}
trap cleanup EXIT

if [[ -n ${OMARCHY_PATH:-} && -d $OMARCHY_PATH/shell ]]; then
  OMARCHY_SOURCE=$(realpath -m -- "$OMARCHY_PATH")
elif [[ -d $ROOT_DIR/../omarchy/shell ]]; then
  OMARCHY_SOURCE=$(realpath -m -- "$ROOT_DIR/../omarchy")
fi

fail() {
  printf 'qml.test.sh: %s\n' "$*" >&2
  exit 1
}

for file in \
  Okomart.qml \
  StorefrontFrame.qml \
  PluginList.qml \
  PluginDetails.qml \
  ScreenshotCarousel.qml \
  ActionDialog.qml \
  Service.qml; do
  [[ -f $ROOT_DIR/$file ]] || fail "missing $file"
done

if command -v qmllint >/dev/null 2>&1; then
  QMLLINT_IMPORT_ARGS=()
  if [[ -n $OMARCHY_SOURCE ]]; then
    QMLLINT_IMPORT_ARGS=(-I "$OMARCHY_SOURCE/shell")
  fi

  qmllint "${QMLLINT_IMPORT_ARGS[@]}" \
    "$ROOT_DIR/Okomart.qml" \
    "$ROOT_DIR/StorefrontFrame.qml" \
    "$ROOT_DIR/PluginList.qml" \
    "$ROOT_DIR/PluginDetails.qml" \
    "$ROOT_DIR/ScreenshotCarousel.qml" \
    "$ROOT_DIR/ActionDialog.qml" \
    "$ROOT_DIR/Service.qml"
fi

run_entrypoint_load_test() {
  local quickshell_bin=""

  if [[ -n ${QUICKSHELL_BIN:-} && -x $QUICKSHELL_BIN ]]; then
    quickshell_bin=$QUICKSHELL_BIN
  elif command -v quickshell >/dev/null 2>&1; then
    quickshell_bin=$(command -v quickshell)
  fi

  if [[ -z $quickshell_bin || -z $OMARCHY_SOURCE ]]; then
    return
  fi

  RUNTIME_TMP=$(mktemp -d)
  local config_dir=$RUNTIME_TMP/config
  local runtime_dir=$RUNTIME_TMP/runtime
  local log=$RUNTIME_TMP/quickshell.log
  mkdir -p -- "$config_dir" "$runtime_dir" "$RUNTIME_TMP/home"
  chmod 0700 "$runtime_dir"
  cp -- "$ROOT_DIR/tests/fixtures/qml-entrypoints/shell.qml" "$config_dir/shell.qml"
  ln -s -- "$OMARCHY_SOURCE/shell/Commons" "$config_dir/Commons"
  ln -s -- "$OMARCHY_SOURCE/shell/Ui" "$config_dir/Ui"

  if ! env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$runtime_dir" \
    HOME="$RUNTIME_TMP/home" \
    OMARCHY_PATH="$OMARCHY_SOURCE" \
    OKOMART_SOURCE_DIR="$ROOT_DIR" \
    QML2_IMPORT_PATH="$OMARCHY_SOURCE/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
    QML_IMPORT_PATH="$OMARCHY_SOURCE/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
    timeout 20 "$quickshell_bin" -p "$config_dir" --no-color >"$log" 2>&1; then
    sed -n '1,220p' "$log" >&2
    fail "Quickshell exited before loading Okomart's entrypoints"
  fi

  if ! grep -Fq 'OKOMART_LOAD_OK service' "$log" \
      || ! grep -Fq 'OKOMART_LOAD_OK panel' "$log"; then
    sed -n '1,220p' "$log" >&2
    fail "Quickshell could not instantiate Okomart's entrypoints"
  fi
}

grep -Fq 'FloatingWindow {' "$ROOT_DIR/Okomart.qml" \
  || fail "Okomart is not hosted in a FloatingWindow"
grep -Fq 'function open(payloadJson)' "$ROOT_DIR/Okomart.qml" \
  || fail "panel lifecycle is missing open(payloadJson)"
grep -Fq 'function close()' "$ROOT_DIR/Okomart.qml" \
  || fail "panel lifecycle is missing close()"
grep -Fq 'import QtQuick.Shapes' "$ROOT_DIR/StorefrontFrame.qml" \
  || fail "storefront is not drawn with QtQuick.Shapes"
grep -Fq 'PathSvg { path: root.roofPath() }' "$ROOT_DIR/StorefrontFrame.qml" \
  || fail "responsive roof path is missing"
if grep -Eq 'readonly property real (left|right|bottom)[[:space:]]*:' \
    "$ROOT_DIR/StorefrontFrame.qml"; then
  fail "storefront overrides a final Item geometry property"
fi
grep -Fq 'wideLayout: window.width >= Style.space(820)' "$ROOT_DIR/Okomart.qml" \
  || fail "responsive master-detail breakpoint is missing"
grep -Fq 'installedOnly ? "installed" : "all"' "$ROOT_DIR/Okomart.qml" \
  || fail "installed-only filter is not wired"
grep -Fq 'OkomartModel.filterPlugins' "$ROOT_DIR/Okomart.qml" \
  || fail "search/filter model is not wired"
grep -Fq 'Qt.Key_PageDown' "$ROOT_DIR/PluginList.qml" \
  || fail "keyboard page navigation is missing"
grep -Fq 'scrollBy(detailsScroll.height * 0.8)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "keyboard details scrolling is missing"
grep -Fq 'OkomartModel.metadataValue(value, fallback)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "detail metadata does not use the tested formatter"
grep -Fq 'OkomartModel.pluginVersionText(plugin)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "detail version does not use the tested formatter"
grep -Fq 'OkomartModel.updateDetailText(plugin)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "detail update status does not use the tested formatter"
grep -Fq 'if (root.installed && root.normalizedUpdateState === "available")' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "uninstalled plugins can expose an irrelevant update badge"
grep -Fq 'OkomartModel.removalBlockReason(plugin)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "dirty Git removal reason does not use the tested model"
grep -Fq 'OkomartModel.canRemovePlugin(plugin)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "dirty Git removal guard does not use the tested model"
grep -Fq 'enabled: root.actionsEnabled && root.removalAllowed' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "dirty Git checkout still exposes an enabled removal action"
grep -Fq 'tooltipText: root.removalBlockReason' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "dirty Git removal guard has no user-facing explanation"
grep -Fq 'Accessible.description: root.removalBlockReason' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "dirty Git removal guard has no accessible explanation"
grep -Fq 'Keys.onLeftPressed' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "keyboard carousel navigation is missing"
grep -Fq 'event.key === Qt.Key_End' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "keyboard carousel end navigation is missing"
grep -Fq 'visible: root.screenshots.length > 0' "$ROOT_DIR/PluginDetails.qml" \
  || fail "zero-image omission is missing"
grep -Fq 'String(root.plugin.catalogCommit || root.catalogRevision)' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "screenshot cache is not keyed by the plugin repository commit"
grep -Fq 'mode === "updates"' "$ROOT_DIR/ActionDialog.qml" \
  || fail "update confirmation mode is missing"
grep -Fq 'event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab' \
  "$ROOT_DIR/ActionDialog.qml" \
  || fail "modal keyboard focus is not trapped"
grep -Fq 'root.scrollReviewBy(reviewScroll.height * 0.8)' \
  "$ROOT_DIR/ActionDialog.qml" \
  || fail "keyboard update-list scrolling is missing"
grep -Fq 'readonly property real reviewHeightBudget' \
  "$ROOT_DIR/ActionDialog.qml" \
  || fail "minimum-height review budgeting is missing"
grep -Fq 'dialogContent.reviewHeightBudget' \
  "$ROOT_DIR/ActionDialog.qml" \
  || fail "review pane does not yield space to action errors"
grep -Fq 'String(snapshot.snapshotId)' "$ROOT_DIR/Okomart.qml" \
  || fail "actions are not bound to the confirmed snapshot"
grep -Fq 'parsed.ok === false || exitCode !== 0' "$ROOT_DIR/Okomart.qml" \
  || fail "snapshot persistence failures are not surfaced as refresh errors"
grep -Fq 'readonly property bool snapshotActionable' "$ROOT_DIR/Okomart.qml" \
  || fail "unpersisted snapshots are not blocked from plugin actions"
grep -Fq '[helperPath, "ack", actionId]' "$ROOT_DIR/Okomart.qml" \
  || fail "completed action status is not acknowledged"

run_entrypoint_load_test

printf 'qml.test.sh: all checks passed\n'
