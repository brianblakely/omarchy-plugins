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
grep -Fq 'event.key === Qt.Key_Home || event.text === "g"' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "lowercase g does not select the first plugin"
grep -Fq 'event.key === Qt.Key_End || event.text === "G"' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "uppercase G does not select the last plugin"
grep -Fq 'list.positionViewAtBeginning()' "$ROOT_DIR/PluginList.qml" \
  || fail "first-plugin navigation does not reveal the top of the list"
grep -Fq 'list.positionViewAtEnd()' "$ROOT_DIR/PluginList.qml" \
  || fail "last-plugin navigation does not reveal the bottom of the list"
grep -Fq 'event.key === Qt.Key_Right || event.key === Qt.Key_L' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list detail handoff is missing its L alias"
grep -Fq 'signal detailsRequested(var plugin)' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin list does not expose directional detail focus"
grep -Fq 'signal searchRequested()' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin list does not expose its top-boundary search handoff"
grep -Fq 'if (!event.isAutoRepeat) root.searchRequested()' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list key repeat can carry focus past the first entry"
if grep -Fq 'if (list.currentIndex <= 0) root.searchRequested()' \
    "$ROOT_DIR/PluginList.qml"; then
  fail "up from the first plugin still hands off during key repeat"
fi
grep -Fq 'if (indexForId(selectedId) !== list.currentIndex)' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "list navigation still queues redundant selection resynchronization"
grep -Fq 'height: root.rowHeight' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list rows do not share a fixed height"
grep -Fq 'id: pluginListScrollNub' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin list is missing its scroll nub"
grep -Fq 'QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list scroll nub does not track whether content overflows"
grep -Fq 'anchors.rightMargin: -root.scrollNubRightOffset' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list scroll nub is not flush with the divider edge"
grep -Fq 'position: list.visibleArea.yPosition' "$ROOT_DIR/PluginList.qml" \
  || fail "detached plugin-list scroll nub does not follow list position"
grep -Fq 'list.contentY = list.originY + nextPosition * list.contentHeight' \
  "$ROOT_DIR/PluginList.qml" \
  || fail "dragging the plugin-list scroll nub does not move the list"
grep -Fq 'width: Style.space(10)' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list scroll nub is too narrow"
grep -Fq 'minimumSize: Math.min(1, Style.space(72)' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list scroll nub can shrink below its usable minimum"
grep -Fq 'radius: 0' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list scroll nub is not rectangular"
grep -Fq 'color: Util.alpha(root.accent, 0.92)' "$ROOT_DIR/PluginList.qml" \
  || fail "plugin-list scroll nub does not retain its hover treatment"
if sed -n '/contentItem: Rectangle {/,/background: Item {}/p' \
    "$ROOT_DIR/PluginList.qml" \
    | grep -Eq 'pluginListScrollNub\.(hovered|pressed)|Behavior on color'; then
  fail "plugin-list scroll nub still changes treatment by interaction state"
fi
grep -Fq 'scrollNubRightOffset: Style.space(13)' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront does not align the plugin-list nub with its divider"
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
grep -Fq 'text: "Select a plugin to see its details."' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "plugin details are missing their empty selection prompt"
grep -Fq 'anchors.centerIn: root' "$ROOT_DIR/PluginDetails.qml" \
  || fail "empty plugin selection prompt is not centered in the details pane"
grep -Fq 'width: Math.max(0, root.width - Style.space(20))' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "empty plugin selection prompt is not sized against the details pane"
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
if grep -Fq 'OkomartModel.updateDetailText(plugin)' "$ROOT_DIR/PluginDetails.qml" \
    || grep -Fq 'plugin.validationError' "$ROOT_DIR/PluginDetails.qml"; then
  fail "plugin details still show status messages below metadata"
fi
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
grep -Fq 'visible: imageIndex === root.displayedIndex' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel does not retain its outgoing preloaded image"
grep -Fq 'imageIndex === root.incomingIndex' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel does not expose its incoming preloaded image"
grep -Fq 'asynchronous: true' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot decoding still blocks plugin-list navigation"
grep -Fq 'cache: false' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel still writes decoded screenshots to the QML cache"
if grep -Fq 'asynchronous: false' "$ROOT_DIR/ScreenshotCarousel.qml" \
    || grep -Fq 'cache: true' "$ROOT_DIR/ScreenshotCarousel.qml"; then
  fail "screenshot carousel uses blocking or cached image loading"
fi
grep -Fq 'id: imageRepeater' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel cannot inspect its preloaded images"
grep -Fq 'model: root.loadedIndices' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel instantiates more than the current neighbor window"
grep -Fq 'function imageForIndex(index)' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot selection does not wait for its decoded image"
grep -Fq '!targetImage || targetImage.status !== Image.Ready' \
  "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "screenshot carousel exposes an image before it is ready"
grep -Fq 'root.imageBecameReady(imageIndex)' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "pending screenshot selection is not completed after decoding"
grep -Fq 'status === Image.Error' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "failed remote screenshots are not detected"
grep -Fq 'root.imageFailed(imageIndex)' "$ROOT_DIR/ScreenshotCarousel.qml" \
  || fail "failed remote screenshots are not omitted"
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
grep -Fq 'revision: root.screenshotRevision' \
  "$ROOT_DIR/PluginDetails.qml" \
  || fail "lazy screenshot revision is not passed into the carousel"
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
grep -Fq 'Qt.openUrlExternally(target)' \
  "$ROOT_DIR/ScreenshotLightbox.qml" \
  || fail "Open Original does not handle both remote and local screenshots"
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
grep -Fq 'interval: 350' "$ROOT_DIR/Okomart.qml" \
  || fail "plugin screenshot discovery is not debounced for 350 ms"
grep -Fq 'onSelectedIdChanged:' "$ROOT_DIR/Okomart.qml" \
  || fail "selection changes do not cancel lazy screenshot discovery"
grep -Fq 'onNarrowShowingDetailsChanged:' "$ROOT_DIR/Okomart.qml" \
  || fail "narrow details lifecycle does not control screenshot discovery"
grep -Fq 'if (mediaProcess.running) mediaProcess.running = false' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "selection changes do not cancel an in-flight screenshot request"
grep -Fq 'requestKey !== mediaRequestKey' "$ROOT_DIR/Okomart.qml" \
  || fail "late screenshot responses are not discarded"
grep -Fq '[helperPath, "cleanup-media", mediaSessionId]' "$ROOT_DIR/Okomart.qml" \
  || fail "generic screenshot sessions are not cleaned on selection changes"
grep -Fq '[helperPath, "cleanup-media", "--all"]' "$ROOT_DIR/Okomart.qml" \
  || fail "abandoned screenshot sessions are not cleaned on launch"
grep -Fq 'mediaProcess.command = [helperPath, "screenshots"' "$ROOT_DIR/Okomart.qml" \
  || fail "details do not request screenshots lazily from the backend"
grep -Fq 'onScreenshotFailed: function(index) { root.omitFailedScreenshot(index) }' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "failed lazy screenshots remain in plugin details"
grep -Fq 'mode === "updates"' "$ROOT_DIR/ActionDialog.qml" \
  || fail "update confirmation mode is missing"
grep -Fq 'mode === "update"' "$ROOT_DIR/ActionDialog.qml" \
  || fail "single-plugin update confirmation mode is missing"
grep -Fq 'then restart the Omarchy shell so every entry point gets a clean load' \
  "$ROOT_DIR/ActionDialog.qml" \
  || fail "install confirmation does not disclose its shell restart"
grep -Fq 'OkomartModel.clickableSourceUrl(plugin)' \
  "$ROOT_DIR/ActionDialog.qml" \
  || fail "install confirmation source does not use the tested URL guard"
grep -Fq 'function openInstallSource(url)' "$ROOT_DIR/ActionDialog.qml" \
  || fail "install confirmation source link has no guarded opener"
grep -Fq 'Qt.openUrlExternally(url)' "$ROOT_DIR/ActionDialog.qml" \
  || fail "install confirmation source does not open externally"
grep -Fq 'id: installSourceLink' "$ROOT_DIR/ActionDialog.qml" \
  || fail "install confirmation source is not independently interactive"
grep -Fq 'Accessible.role: Accessible.Link' "$ROOT_DIR/ActionDialog.qml" \
  || fail "install confirmation source link is not exposed accessibly"
grep -Fq 'cursorShape: Qt.PointingHandCursor' "$ROOT_DIR/ActionDialog.qml" \
  || fail "install confirmation source link does not expose a pointing cursor"
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
  || fail "actions are not bound to the confirmed active generation"
grep -Fq 'exitCode !== 0 || !parsed || parsed.ok !== true' "$ROOT_DIR/Okomart.qml" \
  || fail "background catalog refresh failures are not surfaced"
grep -Fq 'readonly property bool snapshotActionable' "$ROOT_DIR/Okomart.qml" \
  || fail "missing active generations are not blocked from plugin actions"
grep -Fq 'OkomartModel.snapshotConfirmsUpdates(parsed, exitCode)' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "update visibility does not require an independent remote check"
grep -Fq 'visible: root.hasConfirmedUpdates' "$ROOT_DIR/Okomart.qml" \
  || fail "updates button is visible before update availability is confirmed"
if grep -Fq 'visible: root.hasDetectedUpdates' "$ROOT_DIR/Okomart.qml"; then
  fail "updates button still trusts unconfirmed cached update rows"
fi
if ! sed -n '/function open(payloadJson)/,/^  }/p' "$ROOT_DIR/Okomart.qml" \
    | grep -Fq 'updatesConfirmed = false'; then
  fail "reopening Okomart retains stale update confirmation"
fi
if sed -n '/function refresh(force)/,/^  }/p' "$ROOT_DIR/Okomart.qml" \
    | grep -Fq 'updatesConfirmed = false'; then
  fail "manifest refresh incorrectly invalidates session update checks for the active generation"
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
grep -Fq 'cacheProcess.command = [helperPath, "snapshot", sourceDir]' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront does not read the local active catalog first"
grep -Fq 'parsed && Array.isArray(parsed.plugins)' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "cold local snapshots cannot display installed plugins while refresh runs"
grep -Fq 'statusChecking = true' "$ROOT_DIR/Okomart.qml" \
  || fail "local actions are enabled before action status is reconciled"
if ! sed -n '/function open(payloadJson)/,/^  }/p' "$ROOT_DIR/Okomart.qml" \
    | grep -Fq 'loadCachedSnapshot(true)'; then
  fail "every storefront open does not reload local catalog state"
fi
grep -Fq '[helperPath, "refresh", sourceDir]' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront opening does not stage a background manifest refresh"
grep -Fq '[helperPath, "check-updates", sourceDir]' "$ROOT_DIR/Okomart.qml" \
  || fail "installed and self update checks are not independent"
grep -Fq '[helperPath, "enrich", pendingGeneration]' "$ROOT_DIR/Okomart.qml" \
  || fail "pending generations are not enriched separately"
grep -Fq '[helperPath, "promote", pendingGeneration]' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront sign cannot promote the exact pending generation"
if sed -n '/function openActionDialog(mode, plugin, updates)/,/^  }/p' \
    "$ROOT_DIR/Okomart.qml" | grep -Fq 'if (refreshing)'; then
  fail "background refresh blocks actions against the active generation"
fi
grep -Fq 'enabled: root.pendingReady && !root.activatingCatalog' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront sign is interactive without a ready pending generation"
grep -Fq 'Accessible.role: Accessible.Button' "$ROOT_DIR/Okomart.qml" \
  || fail "pending storefront sign has no button role"
grep -Fq 'Qt.Key_Return || event.key === Qt.Key_Enter' "$ROOT_DIR/Okomart.qml" \
  || fail "pending storefront sign cannot be activated from the keyboard"
grep -Fq 'cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "ready storefront sign has no pointer cursor"
grep -Fq 'running: root.pendingReady' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront sign glow does not follow ready pending state"
grep -Fq 'import QtQuick.Effects' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront sign glow does not import the glyph effect"
grep -Fq 'id: signGlow' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront sign is missing its glyph glow"
grep -Fq 'source: signText' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront sign glow is not shaped by the lettering"
grep -Fq 'colorizationColor: Color.accent' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront sign glow does not use the accent color"
grep -Fq 'blurEnabled: true' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront sign lettering does not emit a blurred glow"
if sed -n '/id: signGlow/,/^        }/p' "$ROOT_DIR/Okomart.qml" \
    | grep -Eq '(border\.|radius:)'; then
  fail "storefront sign glow is still a rectangular border"
fi
grep -Fq 'id: signFlickerTimer' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront sign glow has no occasional flicker timer"
grep -Fq '7000 + Math.floor(Math.random() * 9000)' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront sign flicker is not sparse and irregular"
grep -Fq 'id: signFlickerAnimation' "$ROOT_DIR/Okomart.qml" \
  || fail "storefront sign glow has no neon flicker sequence"
[[ $(grep -Fc 'property: "glowFlicker"' "$ROOT_DIR/Okomart.qml") -ge 4 ]] \
  || fail "storefront sign glow does not sputter through a multi-step flicker"
if sed -n '/function applyCatalogActivation(raw, generation)/,/^  }/p' \
    "$ROOT_DIR/Okomart.qml" | grep -Eq '(query|installedOnly|selectedId)[[:space:]]*='; then
  fail "catalog activation resets storefront query, filter, or selection state"
fi
grep -Fq 'selectedId = OkomartModel.resolveSelection(next, selectedId)' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "catalog activation cannot preserve the selected plugin when it remains visible"
selection_line=$(grep -n -F \
  'selectedId = OkomartModel.resolveSelection(next, selectedId)' \
  "$ROOT_DIR/Okomart.qml" | head -n 1 | cut -d: -f1)
model_line=$(grep -n -F 'visiblePlugins = next' "$ROOT_DIR/Okomart.qml" \
  | head -n 1 | cut -d: -f1)
if [[ -z $selection_line || -z $model_line ]] || (( selection_line >= model_line )); then
  fail "plugin-list model is replaced before its selected id is preserved"
fi
grep -Fq 'property bool pluginListResetting: false' "$ROOT_DIR/Okomart.qml" \
  || fail "plugin-list model resets cannot suppress transient selection changes"
grep -Fq 'if (!root.pluginListResetting) root.selectedId = pluginId' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "plugin-list reset can overwrite the preserved selected plugin"
grep -Fq 'if (resetSerial === pluginListResetSerial) pluginListResetting = false' \
  "$ROOT_DIR/Okomart.qml" \
  || fail "plugin-list reset guard is not released after index synchronization"
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
