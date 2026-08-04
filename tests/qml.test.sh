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
  ScreenshotLightbox.qml \
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
    "$ROOT_DIR/ScreenshotLightbox.qml" \
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
grep -Fq '[helperPath,' "$ROOT_DIR/Okomart.qml" \
  || fail "Okomart cannot invoke its window-rule helper"
grep -Fq '"prepare-window",' "$ROOT_DIR/Okomart.qml" \
  || fail "Okomart does not prepare its floating rule before mapping"
grep -Fq 'barGeometry.position,' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "Okomart does not send the live bar position for window sizing"
grep -Fq 'String(barGeometry.size)' "$ROOT_DIR/Okomart.qml" \
  || fail "Okomart does not send the live bar size for window sizing"
grep -Fq 'activeBar.barHidden === true' "$ROOT_DIR/Okomart.qml" \
  || fail "Okomart window sizing does not account for a hidden bar"
grep -Fq 'Number(activeBar.barSize)' "$ROOT_DIR/Okomart.qml" \
  || fail "Okomart window sizing does not read the active bar size"
grep -Fq 'String(activeBar.position' "$ROOT_DIR/Okomart.qml" \
  || fail "Okomart window sizing does not read the active bar position"
grep -Fq 'windowSide = preparedWidth' "$ROOT_DIR/Okomart.qml" \
  || fail "Okomart does not adopt the prepared focused-screen geometry"
grep -Fq 'parsed.prepared === true' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "Okomart does not verify that its map-time rule was registered"
grep -Fq 'function showPreparedWindow()' "$ROOT_DIR/Okomart.qml" \
  || fail "Okomart is missing its post-preparation map step"
if sed -n '/function open(payloadJson)/,/^  }/p' "$ROOT_DIR/Okomart.qml" \
    | grep -Fq 'window.visible = true'; then
  fail "Okomart maps before its floating rule is prepared"
fi
if ! sed -n '/function showPreparedWindow()/,/^  }/p' "$ROOT_DIR/Okomart.qml" \
    | grep -Fq 'window.visible = true'; then
  fail "Okomart does not map after its floating rule is prepared"
fi
if grep -Fq 'Hyprland.dispatch(' "$ROOT_DIR/Okomart.qml"; then
  fail "Okomart bypasses the target Lua window-rule helper"
fi
[[ $(grep -Fc 'implicitWidth: root.windowSide' "$ROOT_DIR/Okomart.qml") -eq 1 ]] \
  || fail "Okomart does not declare a square initial width"
[[ $(grep -Fc 'implicitHeight: root.windowSide' "$ROOT_DIR/Okomart.qml") -eq 1 ]] \
  || fail "Okomart does not declare a square initial height"
grep -Fq 'minimumSize: Qt.size(root.minimumWindowSide, root.minimumWindowSide)' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "Okomart minimum geometry is not square"
grep -Fq 'function open(payloadJson)' "$ROOT_DIR/Okomart.qml" \
  || fail "panel lifecycle is missing open(payloadJson)"
grep -Fq 'function close()' "$ROOT_DIR/Okomart.qml" \
  || fail "panel lifecycle is missing close()"
grep -Fq 'function runtimeVersion(_arg)' "$ROOT_DIR/Okomart.qml" \
  || fail "panel lifecycle cannot report the loaded Okomart version"
if ! sed -n '/function runtimeVersion(_arg)/,/^  }/p' "$ROOT_DIR/Okomart.qml" \
    | grep -Fq 'String(manifest.version)'; then
  fail "runtime version probe does not report the loaded manifest"
fi
grep -Fq 'import QtQuick.Shapes' "$ROOT_DIR/StorefrontFrame.qml" \
  || fail "storefront is not drawn with QtQuick.Shapes"
grep -Fq 'PathSvg { path: root.roofPath() }' "$ROOT_DIR/StorefrontFrame.qml" \
  || fail "responsive roof path is missing"
grep -Fq 'OkomartModel.hyprlandColorComponents(raw)' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront does not parse the effective Hyprland border color"
grep -Fq '"general:col.inactive_border"' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront does not query the OS inactive-border color"
grep -Fq 'import QtQuick.Window' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront cannot use the backing window's attached activity state"
grep -Fq 'focusScope.Window.active ? Color.accent : inactiveBorderColor' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "storefront color does not follow window activity"
grep -Fq 'Behavior on storefrontColor' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront color does not animate between activity states"
grep -Fq 'duration: 539' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront activity animation does not match Omarchy's border duration"
grep -Fq 'easing.type: Easing.BezierSpline' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront activity animation does not use Omarchy's border easing"
grep -Fq 'easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "storefront activity animation does not match Omarchy's easeOutQuint curve"
grep -Fq 'strokeColor: root.storefrontColor' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront line drawing does not use its activity color"
grep -Fq 'color: root.storefrontColor' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront signage does not use its activity color"
grep -Fq 'Window.onActiveChanged: root.refreshInactiveBorderColor()' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "storefront does not refresh the OS color on activity changes"
if grep -Fq 'window.active' "$ROOT_DIR/Okomart.qml" \
    || grep -Fq 'root.Window.active' "$ROOT_DIR/Okomart.qml" \
    || grep -Eq '^[[:space:]]+onActiveChanged: root\.refreshInactiveBorderColor' \
      "$ROOT_DIR/Okomart.qml"; then
  fail "storefront reads activity from unsupported FloatingWindow properties"
fi
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
grep -Fq 'Number(window.devicePixelRatio)' "$ROOT_DIR/Okomart.qml" \
  || fail "adaptive content scaling does not read the output scale"
grep -Fq 'OkomartModel.dpiCompactionScale(' "$ROOT_DIR/Okomart.qml" \
  || fail "high-DPI content compaction is missing"
grep -Fq 'wideLayout: layoutWidth >= wideLayoutBreakpoint' "$ROOT_DIR/Okomart.qml" \
  || fail "responsive master-detail breakpoint ignores compacted layout width"
grep -Fq 'toolbarSingleRow: layoutWidth >= Style.space(420)' "$ROOT_DIR/Okomart.qml" \
  || fail "responsive single-row toolbar ignores compacted layout width"
grep -Fq 'width: parent.width / root.contentScale' "$ROOT_DIR/Okomart.qml" \
  || fail "content canvas does not compensate for adaptive scaling"
grep -Fq 'xScale: root.contentScale' "$ROOT_DIR/Okomart.qml" \
  || fail "adaptive horizontal content scale is missing"
grep -Fq 'yScale: root.contentScale' "$ROOT_DIR/Okomart.qml" \
  || fail "adaptive vertical content scale is missing"
grep -Fq 'readonly property real controlHeight: Math.max(' "$ROOT_DIR/Okomart.qml" \
  || fail "toolbar does not derive one shared control height"
[[ $(grep -Fc 'Layout.preferredHeight: toolbar.controlHeight' \
  "$ROOT_DIR/Okomart.qml") -eq 3 ]] \
  || fail "toolbar search field and buttons do not share a height"
grep -Fq 'OkomartModel.filterPlugins(allPlugins, query, installedOnly)' \
  "$ROOT_DIR/Okomart.qml" \
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
grep -Fq 'signal searchRequested()' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin list does not expose its top-boundary search handoff"
grep -Fq 'if (list.currentIndex <= 0) root.searchRequested()' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "up from the first plugin does not focus search"
grep -Fq 'if (indexForId(selectedId) !== list.currentIndex)' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "list navigation still queues redundant selection resynchronization"
grep -Fq 'height: root.rowHeight' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list rows do not share a fixed height"
grep -Fq 'maximumLineCount: 2' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list descriptions are not limited to two lines"
grep -Fq 'id: installedIndicator' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list rows do not expose an installed marker"
grep -Fq 'visible: row.installed' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list installed marker is not gated by installation state"
grep -Fq 'modelData.versionUpdateAvailable === true' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list update marker does not use detected version updates"
grep -Fq 'text: row.updateAvailable ? "\uf021" : "󰏗"' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list state marker does not match Omarchy's update glyph"
grep -Fq '", installed, update available"' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list update marker is not described accessibly"
if sed -n '/id: installedIndicator/,+10p' "$ROOT_DIR/PluginList.qml" \
    | grep -Fq 'radius:'; then
  fail "plugin-list installed marker is still rendered as a dot"
fi
grep -Fq 'modelData.installed === true' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list installed marker does not use the catalog installation state"
grep -Fq 'contentHeight: detailsColumn.implicitHeight' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details do not expose their scrollable content height"
grep -Fq 'scrollDownAndMaybeFocus(detailsScroll.height * 0.8)' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "keyboard details scrolling is missing"
grep -Fq 'function focusFirstAction()' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details cannot focus their first available action"
grep -Fq 'function firstActionButton()' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details cannot identify their first available action"
grep -Fq 'signal pluginListRequested()' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details do not expose their leftward list handoff"
grep -Fq 'if (event.key === Qt.Key_Left || event.key === Qt.Key_H)' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details do not handle their leftward list boundary"
[[ $(grep -Fc 'root.pluginListRequested()' \
  "$ROOT_DIR/PluginDetails.qml") -eq 3 ]] \
  || fail "every plugin action must directly return leftward focus to the list"
grep -Fq 'function actionHasFocus()' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details cannot distinguish action focus from viewport focus"
grep -Fq 'if (actionHasFocus()) searchRequested()' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "up from a topmost focused action does not return to search"
grep -Fq 'else if (!focusFirstAction()) searchRequested()' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "up from the topmost detail viewport does not focus its first action"
grep -Fq 'onActionsEnabledChanged: if (actionsEnabled && actionFocusPending)' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "detail focus handoff is lost during a background refresh"
grep -Fq 'function itemFullyVisible(item)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details cannot detect a fully visible screenshot carousel"
grep -Fq 'screenshots.length <= 1 || !itemFullyVisible(screenshotsView)' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details focus an incomplete or single-image carousel"
grep -Fq 'screenshotsView.focusControls()' "$ROOT_DIR/PluginDetails.qml" \
  || fail "fully visible screenshots do not receive keyboard control focus"
grep -Fq 'scrollDownAndMaybeFocus(Style.space(42))' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "downward detail scrolling does not consider carousel focus"
grep -Fq 'event.key === Qt.Key_Up || event.key === Qt.Key_K' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin-details K navigation is missing"
grep -Fq 'OkomartModel.metadataValue(value, fallback)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "detail metadata does not use the tested formatter"
grep -Fq 'OkomartModel.pluginVersionText(plugin)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "detail version does not use the tested formatter"
grep -Fq 'OkomartModel.clickableSourceUrl(plugin)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin source links do not use the tested URL guard"
grep -Fq 'Qt.openUrlExternally(url)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin source is not opened externally"
grep -Fq '? Accessible.Link : Accessible.StaticText' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin source link is not exposed accessibly"
grep -Fq 'cursorShape: Qt.PointingHandCursor' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin source link does not expose a pointing cursor"
grep -Fq 'OkomartModel.updateDetailText(plugin)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "detail update status does not use the tested formatter"
if grep -Eqi 'badge|detailBadges' "$ROOT_DIR/PluginDetails.qml" \
    || grep -Fq 'statusText' "$ROOT_DIR/PluginList.qml" \
    || grep -Fq 'return "New"' "$ROOT_DIR/PluginList.qml" \
    || grep -Eq 'function (catalogChange|pluginBadges)' \
      "$ROOT_DIR/OkomartModel.js"; then
  fail "plugin badge feature is still present"
fi
if grep -Fq 'modelData.enabled' "$ROOT_DIR/PluginList.qml" \
    || grep -Eqi '"[^"]*enabled[^"]*"' "$ROOT_DIR/PluginList.qml"; then
  fail "plugin list still renders an enabled-state indicator"
fi
grep -Fq 'if (state === "available" || state === "current") return ""' \
  "$ROOT_DIR/OkomartModel.js" \
  || fail "plugin details expose routine update status snippets"
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
grep -Fq 'event.key === Qt.Key_Home' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "keyboard carousel home navigation is missing"
if grep -Fq 'BorderSurface {' "$ROOT_DIR/ScreenshotCarousel.qml"; then
  fail "plugin screenshots still have a surrounding frame"
fi
grep -Fq 'model: root.imageCount' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot page dots do not represent every image"
grep -Fq 'function focusControls()' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel does not expose its keyboard controls"
grep -Fq 'function reset()' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel does not expose a complete transition reset"
if ! sed -n '/function focusControls()/,/^  }/p' \
    "$ROOT_DIR/ScreenshotCarousel.qml" | grep -Fq 'root.forceActiveFocus()'; then
  fail "screenshot carousel does not focus its neutral keyboard container"
fi
grep -Fq 'screenshotsView.reset()' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin changes bypass the screenshot carousel transition reset"
if grep -Fq 'screenshotsView.currentIndex =' "$ROOT_DIR/PluginDetails.qml"; then
  fail "plugin changes mutate only part of the screenshot carousel state"
fi
if grep -Fq 'focusable: true' "$ROOT_DIR/ScreenshotCarousel.qml"; then
  fail "screenshot dots expose an unexpected active focus treatment"
fi
grep -Fq 'visible: index === root.displayedIndex' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel does not retain its outgoing preloaded image"
grep -Fq 'index === root.incomingIndex' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel does not expose its incoming preloaded image"
grep -Fq 'asynchronous: true' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot decoding still blocks plugin-list navigation"
grep -Fq 'cache: true' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel does not retain decoded images"
if grep -Fq 'asynchronous: false' "$ROOT_DIR/ScreenshotCarousel.qml" \
    || grep -Fq 'cache: false' "$ROOT_DIR/ScreenshotCarousel.qml"; then
  fail "screenshot carousel uses blocking or uncached image loading"
fi
grep -Fq 'id: imageRepeater' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel cannot inspect its preloaded images"
grep -Fq 'imageRepeater.itemAt(targetIndex)' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot selection does not wait for its decoded image"
grep -Fq '!targetImage || targetImage.status !== Image.Ready' \
  "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel exposes an image before it is ready"
grep -Fq 'root.imageBecameReady(index)' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "pending screenshot selection is not completed after decoding"
grep -Fq 'import QtQuick.Effects' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel cannot apply Omarchy's wallpaper reveal mask"
grep -Fq 'import QtQuick.Shapes' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel cannot draw Omarchy's wallpaper reveal mask"
grep -Fq 'property: "revealProgress"' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel does not animate its wipe progress"
grep -Fq 'duration: 420' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot wipe does not match Omarchy's wallpaper duration"
grep -Fq 'easing.type: Easing.InOutCubic' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot wipe does not match Omarchy's wallpaper easing"
grep -Fq 'maskSource: revealMask' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot wipe does not use its reveal mask"
grep -Fq 'maskThresholdMin: 0.5' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot wipe does not match Omarchy's mask threshold"
grep -Fq 'maskSpreadAtMin: 0.02' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot wipe does not match Omarchy's mask edge spread"
grep -Fq 'readonly property real slant: -0.18' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot wipe does not match Omarchy's diagonal slant"
grep -Fq 'readonly property real spread: reach * root.revealProgress' \
  "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot wipe does not expand Omarchy's center reveal"
if grep -Fq 'id: previousButton' "$ROOT_DIR/ScreenshotCarousel.qml" \
    || grep -Fq 'id: nextButton' "$ROOT_DIR/ScreenshotCarousel.qml" \
    || grep -Fq 'Button {' "$ROOT_DIR/ScreenshotCarousel.qml"; then
  fail "screenshot carousel still exposes onscreen arrow controls"
fi
grep -Fq 'implicitHeight: visible ? imageHeight + paginationGap + paginationHeight : 0' \
  "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel does not reserve layout space for its dots"
grep -Fq 'anchors.top: carouselContent.bottom' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot dots are not laid out below the image"
grep -Fq 'width: Style.space(10)' \
  "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot dots do not share the larger visual size"
if grep -Eq 'width: index === root\.currentIndex' \
    "$ROOT_DIR/ScreenshotCarousel.qml"; then
  fail "active screenshot dots still change size"
fi
grep -Fq 'width: Style.space(18)' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot dots do not have a generous click target"
grep -Fq 'cursorShape: Qt.PointingHandCursor' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot dots do not advertise pointer interaction"
grep -Fq 'onClicked: root.select(index)' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot dots do not select their corresponding image"
grep -Fq 'Accessible.onPressAction: root.select(index)' \
  "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot dots cannot be activated accessibly"
grep -Fq 'signal imageActivated(int index)' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot images cannot request their larger view"
grep -Fq 'onClicked: root.imageActivated(root.currentIndex)' \
  "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "clicking a screenshot does not request its larger view"
grep -Fq 'function showInstant(index)' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "thumbnail and lightbox carousels cannot synchronize selection"
grep -Fq 'visible: root.screenshots.length > 0' "$ROOT_DIR/PluginDetails.qml" \
  || fail "zero-image omission is missing"
grep -Fq 'String(root.plugin.catalogCommit || root.catalogRevision)' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "screenshot cache is not keyed by the plugin repository commit"
grep -Fq 'signal screenshotRequested(int index)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details do not forward screenshot expansion requests"
grep -Fq 'onImageActivated: function(index) { root.screenshotRequested(index) }' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin screenshots are not connected to the lightbox request"
grep -Fq 'function restoreScreenshot(index)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details cannot restore lightbox selection and focus"
grep -Fq 'screenshotsView.showInstant(index)' "$ROOT_DIR/PluginDetails.qml" \
  || fail "lightbox selection is not restored to the thumbnail carousel"
grep -Fq 'function openFor(nextImages, nextRevision, index, nextPluginName)' \
  "$ROOT_DIR/ScreenshotLightbox.qml" \
  || fail "screenshot lightbox cannot open with the selected screenshot"
grep -Fq 'anchors.margins: Style.space(16)' "$ROOT_DIR/ScreenshotLightbox.qml" \
  || fail "screenshot lightbox does not span Okomart's interior"
if grep -Fq 'borderSpec:' "$ROOT_DIR/ScreenshotLightbox.qml" \
    || grep -Fq 'border.width:' "$ROOT_DIR/ScreenshotLightbox.qml"; then
  fail "screenshot lightbox still draws a border"
fi
grep -Fq 'text: root.pluginName' "$ROOT_DIR/ScreenshotLightbox.qml" \
  || fail "screenshot lightbox heading does not use the plugin name"
if grep -Eq 'screenshot.*of.*imageCount|currentIndex.*of' \
    "$ROOT_DIR/ScreenshotLightbox.qml"; then
  fail "screenshot lightbox duplicates dot pagination in its heading"
fi
grep -Fq 'imageHeightOverride: Math.max(1, height - paginationGap - paginationHeight)' \
  "$ROOT_DIR/ScreenshotLightbox.qml" \
  || fail "screenshot lightbox does not give the image its available height"
grep -Fq 'imageInteractive: false' "$ROOT_DIR/ScreenshotLightbox.qml" \
  || fail "the enlarged screenshot recursively reopens its lightbox"
grep -Fq 'imageNavigationInteractive: true' "$ROOT_DIR/ScreenshotLightbox.qml" \
  || fail "the enlarged screenshot does not enable split image navigation"
grep -Fq 'property bool imageNavigationInteractive: false' \
  "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel cannot opt into split image navigation"
if [[ $(grep -Fc \
    'enabled: root.imageNavigationInteractive && root.imageCount > 1' \
    "$ROOT_DIR/ScreenshotCarousel.qml") -ne 2 ]]; then
  fail "lightbox image halves remain clickable without multiple screenshots"
fi
grep -Fq 'onClicked: root.select(root.currentIndex - 1)' \
  "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "the left lightbox image half does not select the previous screenshot"
grep -Fq 'onClicked: root.select(root.currentIndex + 1)' \
  "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "the right lightbox image half does not select the next screenshot"
if [[ $(grep -Fc \
    'cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor' \
    "$ROOT_DIR/ScreenshotCarousel.qml") -ne 3 ]]; then
  fail "disabled screenshot image interactions still expose a clickable cursor"
fi
grep -Fq 'text: "Open Original"' "$ROOT_DIR/ScreenshotLightbox.qml" \
  || fail "screenshot lightbox is missing its Open Original action"
grep -Fq 'Qt.openUrlExternally(Util.fileUrl(currentPath))' \
  "$ROOT_DIR/ScreenshotLightbox.qml" \
  || fail "Open Original does not use the default native image viewer"
grep -Fq 'event.key === Qt.Key_Escape' "$ROOT_DIR/ScreenshotLightbox.qml" \
  || fail "screenshot lightbox cannot be dismissed with Escape"
grep -Fq 'event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab' \
  "$ROOT_DIR/ScreenshotLightbox.qml" \
  || fail "screenshot lightbox does not trap keyboard focus"
grep -Fq 'onScreenshotRequested: function(index) { root.openScreenshotLightbox(index) }' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "Okomart does not open its screenshot lightbox"
grep -Fq 'onDismissed: function(index) { pluginDetails.restoreScreenshot(index) }' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "closing the lightbox does not restore screenshot focus"
grep -Fq 'mode === "updates"' "$ROOT_DIR/ActionDialog.qml" \
  || fail "update confirmation mode is missing"
grep -Fq 'mode === "update"' "$ROOT_DIR/ActionDialog.qml" \
  || fail "single-plugin update confirmation mode is missing"
grep -Fq 'return "Okomart will update " + pluginName(plugin)' \
  "$ROOT_DIR/ActionDialog.qml" \
  || fail "single-plugin update confirmation uses unexpected scope wording"
if grep -Fq 'will update only' "$ROOT_DIR/ActionDialog.qml"; then
  fail "single-plugin update confirmation still says only"
fi
grep -Fq 'if (mode === "updates") return "Apply plugin updates?"' \
  "$ROOT_DIR/ActionDialog.qml" \
  || fail "update confirmation title does not use neutral wording"
if grep -Fq '"Apply all safe updates?"' "$ROOT_DIR/ActionDialog.qml"; then
  fail "update confirmation still describes updates as safe"
fi
grep -Fq 'signal confirmed(var selectedUpdateIds)' "$ROOT_DIR/ActionDialog.qml" \
  || fail "update confirmation does not return the selected update ids"
grep -Fq 'selectedUpdateIds.length > 0' "$ROOT_DIR/ActionDialog.qml" \
  || fail "update confirmation allows an empty selection"
grep -Fq 'OkomartModel.selectableUpdates(updates, selfPluginId)' \
  "$ROOT_DIR/ActionDialog.qml" \
  || fail "update confirmation does not place Okomart first"
grep -Fq 'delegate: QQC.CheckBox {' "$ROOT_DIR/ActionDialog.qml" \
  || fail "update confirmation rows are not selectable"
grep -Fq 'checked: root.isUpdateSelected(modelData)' "$ROOT_DIR/ActionDialog.qml" \
  || fail "update confirmation choices do not reflect selection state"
if sed -n \
    '/model: root.mode === "updates" ? root.eligibleUpdates : \[\]/,/model: root.mode === "updates" ? root.blockedUpdates : \[\]/p' \
    "$ROOT_DIR/ActionDialog.qml" | grep -Fq 'BorderSurface {'; then
  fail "updateable confirmation items still have individual frames"
fi
if ! sed -n '/id: reviewScroll/,/id: reviewColumn/p' \
    "$ROOT_DIR/ActionDialog.qml" \
    | grep -Fq 'visible: root.mode === "results"'; then
  fail "update confirmation list still has an outer outline"
fi
grep -Fq 'root.confirmsUpdate' "$ROOT_DIR/ActionDialog.qml" \
  || fail "update confirmation dialog does not distinguish its outer frame"
grep -Fq '? Border.none()' "$ROOT_DIR/ActionDialog.qml" \
  || fail "update confirmation dialog still has an outer frame"
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
grep -Fq 'OkomartModel.snapshotConfirmsUpdates(parsed, exitCode)' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "update visibility does not require a tested fresh snapshot"
grep -Fq 'visible: root.hasConfirmedUpdates' "$ROOT_DIR/Okomart.qml" \
  || fail "updates button is visible before update availability is confirmed"
if grep -Fq 'visible: root.hasDetectedUpdates' "$ROOT_DIR/Okomart.qml"; then
  fail "updates button still trusts unconfirmed cached update rows"
fi
if ! sed -n '/function open(payloadJson)/,/^  }/p' "$ROOT_DIR/Okomart.qml" \
    | grep -Fq 'updatesConfirmed = false'; then
  fail "reopening Okomart retains stale update confirmation"
fi
if ! sed -n '/function refresh()/,/^  }/p' "$ROOT_DIR/Okomart.qml" \
    | grep -Fq 'updatesConfirmed = false'; then
  fail "refreshing Okomart leaves update availability confirmed"
fi
grep -Fq 'p.versionUpdateAvailable === true' "$ROOT_DIR/Okomart.qml" \
  || fail "global updates are not gated by manifest version"
grep -Fq 'onUpdateRequested: function(plugin)' "$ROOT_DIR/Okomart.qml" \
  || fail "single-plugin update is not connected to the storefront"
if ! sed -n \
    '/function actionIncludesSelf(kind, selectedUpdateIds)/,/^  }/p' \
    "$ROOT_DIR/Okomart.qml" \
    | grep -Fq 'selectedUpdateIds.indexOf(pluginId) >= 0'; then
  fail "selected batch updates do not detect when Okomart replaces itself"
fi
grep -Fq 'command.push(JSON.stringify(Array.isArray(selectedUpdateIds)' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "selected update ids are not passed to the backend"
grep -Fq 'root.beginAction("update-all", null, selectedUpdateIds)' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "update-all does not use the dialog selection"
if ! sed -n '/function actionStarted(raw, exitCode)/,/^  }/p' \
    "$ROOT_DIR/Okomart.qml" \
    | grep -Fq 'requestClose()'; then
  fail "a queued self-update leaves the old Okomart panel loaded"
fi
grep -Fq '[helperPath, "cached"]' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront does not load its persisted snapshot first"
grep -Fq 'parsed && parsed.ok === true && Array.isArray(parsed.plugins)' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "storefront does not require a successful cached snapshot"
grep -Fq 'statusChecking = true' "$ROOT_DIR/Okomart.qml" \
  || fail "cached actions are enabled before action status is reconciled"
grep -Fq 'if (catalogLoaded) loadActionStatus()' "$ROOT_DIR/Okomart.qml" \
  || fail "reopening the storefront does not preserve loaded catalog data"
grep -Fq 'onDetailsRequested: function(plugin)' "$ROOT_DIR/Okomart.qml" \
  || fail "plugin-list directional focus is not connected"
grep -Fq 'Qt.callLater(pluginDetails.focusFirstAction)' "$ROOT_DIR/Okomart.qml" \
  || fail "rightward list navigation does not focus the first detail action"
[[ $(grep -Fc 'onSearchRequested: searchField.forceActiveFocus()' \
  "$ROOT_DIR/Okomart.qml") -eq 2 ]] \
  || fail "list and detail top-boundary navigation are not connected to search"
grep -Fq 'onPluginListRequested: root.focusPluginListFromSearch()' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "leftward detail navigation is not connected to the plugin list"
if ! sed -n '/function showPreparedWindow()/,/^  }/p' "$ROOT_DIR/Okomart.qml" \
    | grep -Fq 'Qt.callLater(focusInitialPluginList)'; then
  fail "Okomart does not focus the plugin list after its window maps"
fi
grep -Fq 'function focusFirstItem()' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin list cannot focus its first item"
grep -Fq 'function focusCurrentItem()' "$ROOT_DIR/PluginList.qml" \
  || fail "directional navigation cannot focus the selected plugin"
[[ $(grep -Fc 'focus: true' "$ROOT_DIR/PluginList.qml") -ge 1 ]] \
  || fail "the actual plugin ListView is not the nested focus default"
grep -Fq 'initialFocusTimer.restart()' "$ROOT_DIR/Okomart.qml" \
  || fail "initial focus is not retried after the window becomes active"
grep -Fq 'function focusPluginListFromSearch()' "$ROOT_DIR/Okomart.qml" \
  || fail "empty search cannot focus the plugin list"
grep -Fq 'function focusPluginDetailsFromSearch()' "$ROOT_DIR/Okomart.qml" \
  || fail "search cannot focus plugin details"
grep -Fq 'Qt.callLater(pluginDetails.focusViewport)' "$ROOT_DIR/Okomart.qml" \
  || fail "down from search incorrectly focuses a detail action"
grep -Fq 'Keys.onLeftPressed: function(event)' "$ROOT_DIR/Okomart.qml" \
  || fail "search has no empty-left navigation"
[[ $(grep -Fc 'event.accepted = false' "$ROOT_DIR/Okomart.qml") -ge 2 ]] \
  || fail "nonempty search intercepts normal left/right cursor movement"
grep -Fq 'if (text.length === 0)' "$ROOT_DIR/Okomart.qml" \
  || fail "empty-search rightward navigation is missing"
grep -Fq 'event.key === Qt.Key_Left || event.key === Qt.Key_H' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "toolbar H navigation is missing"
grep -Fq 'iconText: root.installedOnly ? "󰈲" : "󱓯"' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "installed filter does not distinguish filtered and unfiltered glyphs"
grep -Fq 'iconText: "\uf021"' "$ROOT_DIR/Okomart.qml" \
  || fail "updates button does not use Omarchy's update-available glyph"
if grep -Fq ' safe plugin ' "$ROOT_DIR/Okomart.qml"; then
  fail "updates button still describes routine updates as safe"
fi
if grep -Fq 'text: root.installedOnly ? "Installed" : "All"' \
    "$ROOT_DIR/Okomart.qml" \
    || grep -Fq 'text: root.safeUpdateCount > 0 ? "Updates "' \
      "$ROOT_DIR/Okomart.qml"; then
  fail "toolbar buttons retain their old text labels"
fi
if grep -Fq 'Catalog refreshed' "$ROOT_DIR/Okomart.qml" \
    || grep -Fq 'Catalog is current.' "$ROOT_DIR/Okomart.qml" \
    || grep -Fq 'Refreshing catalog…' "$ROOT_DIR/Okomart.qml"; then
  fail "catalog refreshes still show an affirmative or informational notice"
fi
grep -Fq 'emptyText: root.catalogLoaded' "$ROOT_DIR/Okomart.qml" \
  || fail "plugin list exposes an empty result before cache loading finishes"
grep -Fq 'root.beginAction("update", plugin)' "$ROOT_DIR/Okomart.qml" \
  || fail "single-plugin update does not start a scoped backend action"
grep -Fq 'import QtQuick.Layouts' "$ROOT_DIR/Okomart.qml" \
  || fail "responsive toolbar layout import is missing"
grep -Fq 'GridLayout {' "$ROOT_DIR/Okomart.qml" \
  || fail "toolbar does not switch rows through a responsive grid"
grep -Fq 'columns: root.toolbarSingleRow ? 3 : 2' "$ROOT_DIR/Okomart.qml" \
  || fail "toolbar does not switch between wide and narrow arrangements"
grep -Fq 'Layout.columnSpan: root.toolbarSingleRow ? 1 : 2' "$ROOT_DIR/Okomart.qml" \
  || fail "toolbar search field does not wrap below its breakpoint"
grep -Fq 'anchors.rightMargin: storefront.frameInset + root.headerEdgeInset' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "toolbar does not mirror the signage edge inset"
grep -Fq 'x: storefront.frameLeft + root.headerEdgeInset' "$ROOT_DIR/Okomart.qml" \
  || fail "signage does not use the shared edge inset"
grep -Fq 'y: root.toolbarSingleRow ? root.bodyTop - Style.space(45) : root.bodyTop - Style.space(70)' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "tested toolbar vertical adjustment was lost"
grep -Fq 'Layout.preferredWidth: Style.space(150)' "$ROOT_DIR/Okomart.qml" \
  || fail "tested search-field width adjustment was lost"
if grep -Fq 'toolbar.controlSpacing' "$ROOT_DIR/Okomart.qml" \
    || grep -Fq 'updatedButton' "$ROOT_DIR/Okomart.qml"; then
  fail "toolbar retains obsolete manual positioning"
fi
grep -Fq '[helperPath, "ack", actionId]' "$ROOT_DIR/Okomart.qml" \
  || fail "completed action status is not acknowledged"
grep -Fq 'OkomartModel.reconcileActionSnapshot(' "$ROOT_DIR/Okomart.qml" \
  || fail "completed plugin actions wait for a network refresh before updating the UI"
if ! sed -n '/var results = Array.isArray(parsed.results)/,/refresh()/p' \
    "$ROOT_DIR/Okomart.qml" \
    | grep -Fq 'OkomartModel.reconcileActionSnapshot('; then
  fail "completed plugin actions are not reconciled before the network refresh"
fi

run_entrypoint_load_test

printf 'qml.test.sh: all checks passed\n'
