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
if sed -n '/function roofPath()/,/^  }/p' "$ROOT_DIR/StorefrontFrame.qml" \
    | grep -Fq '+ " Z"'; then
  fail "roof path closes across separate trim segments"
fi
grep -Fq '+ " M " + frameLeft + " " + eaveY' "$ROOT_DIR/StorefrontFrame.qml" \
  || fail "left roof trim is not an independent vertical segment"
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
if grep -Fq 'onEntered: list.currentIndex' "$ROOT_DIR/PluginList.qml"; then
  fail "mouse hover changes the active plugin"
fi
grep -Fq 'Qt.Key_PageDown' "$ROOT_DIR/PluginList.qml" \
  || fail "keyboard page navigation is missing"
grep -Fq 'event.key === Qt.Key_Down || event.key === Qt.Key_J' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list J navigation is missing"
grep -Fq 'event.key === Qt.Key_Up || event.key === Qt.Key_K' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list K navigation is missing"
grep -Fq 'event.key === Qt.Key_Right || event.key === Qt.Key_L' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list detail handoff is missing its L alias"
grep -Fq 'signal detailsRequested(var plugin)' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin list does not expose directional detail focus"
grep -Fq 'height: root.rowHeight' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list rows do not share a fixed height"
grep -Fq 'maximumLineCount: 2' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list descriptions are not limited to two lines"
grep -Fq 'contentHeight: detailsColumn.implicitHeight' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details do not expose their scrollable content height"
grep -Fq 'scrollBy(detailsScroll.height * 0.8)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "keyboard details scrolling is missing"
grep -Fq 'function focusFirstAction()' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details cannot focus their first available action"
grep -Fq 'onActionsEnabledChanged: if (actionsEnabled && actionFocusPending)' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "detail focus handoff is lost during a background refresh"
grep -Fq 'currentFlick.contentY <= 0.5' "$ROOT_DIR/PluginDetails.qml" \
  || fail "top-of-details navigation does not return to search"
grep -Fq 'event.key === Qt.Key_Up || event.key === Qt.Key_K' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin-details K navigation is missing"
grep -Fq 'OkomartModel.metadataValue(value, fallback)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "detail metadata does not use the tested formatter"
grep -Fq 'OkomartModel.pluginVersionText(plugin)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "detail version does not use the tested formatter"
grep -Fq 'OkomartModel.updateDetailText(plugin)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "detail update status does not use the tested formatter"
if grep -Fq 'badges.push("Available")' "$ROOT_DIR/PluginDetails.qml"; then
  fail "plugin details still expose the Available badge"
fi
if grep -Fq 'badges.push(root.plugin.enabled ? "Installed' \
    "$ROOT_DIR/PluginDetails.qml"; then
  fail "plugin details still expose the Installed badge"
fi
grep -Fq 'if (state === "current") return ""' "$ROOT_DIR/OkomartModel.js" \
  || fail "plugin details still expose an up-to-date status snippet"
if grep -Eq '\{ label: "(ID|Kinds|License|State)"' "$ROOT_DIR/PluginDetails.qml"; then
  fail "plugin details expose internal or unwanted metadata"
fi
grep -Fq 'text: "Install"' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details do not use the concise Install label"
grep -Fq 'signal updateRequested(var plugin)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details do not expose a single-plugin update action"
grep -Fq 'visible: root.updateAvailable' "$ROOT_DIR/PluginDetails.qml" \
  || fail "single-plugin Update is not gated by version availability"
description_line=$(grep -n -F \
  'text: root.hasPlugin ? root.value(root.plugin.description' \
  "$ROOT_DIR/PluginDetails.qml" | cut -d: -f1)
install_line=$(grep -n -F 'id: installButton' "$ROOT_DIR/PluginDetails.qml" | cut -d: -f1)
metadata_line=$(grep -n -F 'id: metadata' "$ROOT_DIR/PluginDetails.qml" | cut -d: -f1)
if [[ -z $description_line || -z $install_line || -z $metadata_line ]] \
    || (( description_line >= install_line || install_line >= metadata_line )); then
  fail "plugin actions are not directly below the description"
fi
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
grep -Fq 'event.key === Qt.Key_Left || event.key === Qt.Key_H' \
  "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "keyboard carousel navigation is missing"
grep -Fq 'event.key === Qt.Key_Right || event.key === Qt.Key_L' \
  "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "keyboard carousel L navigation is missing"
grep -Fq 'event.key === Qt.Key_End' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "keyboard carousel end navigation is missing"
if grep -Fq 'BorderSurface {' "$ROOT_DIR/ScreenshotCarousel.qml"; then
  fail "plugin screenshots still have a surrounding frame"
fi
grep -Fq 'id: pageDots' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel does not use page dots"
grep -Fq 'model: root.imageCount' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot page dots do not represent every image"
grep -Fq 'width: Style.space(24)' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel arrows are not compact"
previous_line=$(grep -n -F 'id: previousButton' \
  "$ROOT_DIR/ScreenshotCarousel.qml" | cut -d: -f1)
dots_line=$(grep -n -F 'id: pageDots' \
  "$ROOT_DIR/ScreenshotCarousel.qml" | cut -d: -f1)
next_line=$(grep -n -F 'id: nextButton' \
  "$ROOT_DIR/ScreenshotCarousel.qml" | cut -d: -f1)
if [[ -z $previous_line || -z $dots_line || -z $next_line ]] \
    || (( previous_line >= dots_line || dots_line >= next_line )); then
  fail "screenshot arrows do not flank the page dots"
fi
grep -Fq 'visible: root.screenshots.length > 0' "$ROOT_DIR/PluginDetails.qml" \
  || fail "zero-image omission is missing"
grep -Fq 'String(root.plugin.catalogCommit || root.catalogRevision)' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "screenshot cache is not keyed by the plugin repository commit"
grep -Fq 'mode === "updates"' "$ROOT_DIR/ActionDialog.qml" \
  || fail "update confirmation mode is missing"
grep -Fq 'mode === "update"' "$ROOT_DIR/ActionDialog.qml" \
  || fail "single-plugin update confirmation mode is missing"
grep -Fq 'event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab' \
  "$ROOT_DIR/ActionDialog.qml" \
  || fail "modal keyboard focus is not trapped"
grep -Fq 'root.scrollReviewBy(reviewScroll.height * 0.8)' \
  "$ROOT_DIR/ActionDialog.qml" \
  || fail "keyboard update-list scrolling is missing"
grep -Fq 'event.key === Qt.Key_Down || event.key === Qt.Key_J' \
  "$ROOT_DIR/ActionDialog.qml" \
  || fail "update-review J navigation is missing"
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
grep -Fq 'p.versionUpdateAvailable === true' "$ROOT_DIR/Okomart.qml" \
  || fail "global updates are not gated by manifest version"
grep -Fq 'onUpdateRequested: function(plugin)' "$ROOT_DIR/Okomart.qml" \
  || fail "single-plugin update is not connected to the storefront"
grep -Fq '[helperPath, "cached"]' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront does not load its persisted snapshot first"
grep -Fq 'parsed && parsed.ok !== false && Array.isArray(parsed.plugins)' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "storefront accepts a failed snapshot as cached catalog data"
grep -Fq 'statusChecking = true' "$ROOT_DIR/Okomart.qml" \
  || fail "cached actions are enabled before action status is reconciled"
grep -Fq 'if (catalogLoaded) loadActionStatus()' "$ROOT_DIR/Okomart.qml" \
  || fail "reopening the storefront does not preserve loaded catalog data"
grep -Fq 'onDetailsRequested: function(plugin)' "$ROOT_DIR/Okomart.qml" \
  || fail "plugin-list directional focus is not connected"
grep -Fq 'Qt.callLater(pluginDetails.focusFirstAction)' "$ROOT_DIR/Okomart.qml" \
  || fail "rightward list navigation does not focus the first detail action"
grep -Fq 'onSearchRequested: searchField.forceActiveFocus()' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "top-of-details navigation is not connected to search"
grep -Fq 'if (text.length === 0)' "$ROOT_DIR/Okomart.qml" \
  || fail "empty-search rightward navigation is missing"
grep -Fq 'event.key === Qt.Key_Left || event.key === Qt.Key_H' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "toolbar H navigation is missing"
grep -Fq 'emptyText: root.catalogLoaded' "$ROOT_DIR/Okomart.qml" \
  || fail "plugin list exposes an empty result before cache loading finishes"
grep -Fq 'root.beginAction("update", plugin)' "$ROOT_DIR/Okomart.qml" \
  || fail "single-plugin update does not start a scoped backend action"
grep -Fq 'Math.min(Style.space(420)' "$ROOT_DIR/Okomart.qml" \
  || fail "wide-layout search field has no responsive width cap"
grep -Fq '[helperPath, "ack", actionId]' "$ROOT_DIR/Okomart.qml" \
  || fail "completed action status is not acknowledged"

run_entrypoint_load_test

printf 'qml.test.sh: all checks passed\n'
