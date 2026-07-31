var FILTER_ALL = "all"
var FILTER_INSTALLED = "installed"
var DIRTY_GIT_REMOVAL_REASON =
  "Uninstall is disabled while this Git checkout has local changes. Commit, stash, or discard them first."

var SUPPORTED_SCREENSHOT_EXTENSIONS = {
  bmp: true,
  gif: true,
  jpeg: true,
  jpg: true,
  png: true,
  webp: true
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function stringValue(value) {
  return value === undefined || value === null ? "" : String(value)
}

function trimmedString(value) {
  return stringValue(value).trim()
}

function lowerString(value) {
  return trimmedString(value).toLowerCase()
}

function own(object, key) {
  return isRecord(object) && Object.prototype.hasOwnProperty.call(object, key)
}

function recordField(record, key) {
  if (!isRecord(record)) return undefined
  if (own(record, key) && record[key] !== undefined && record[key] !== null)
    return record[key]

  var manifest = isRecord(record.manifest) ? record.manifest : null
  return manifest && own(manifest, key) ? manifest[key] : undefined
}

function firstText(values, fallback) {
  for (var i = 0; i < values.length; i++) {
    var value = trimmedString(values[i])
    if (value.length > 0) return value
  }
  return fallback === undefined ? "" : trimmedString(fallback)
}

function pluginId(plugin) {
  return trimmedString(recordField(plugin, "id"))
}

function pluginName(plugin) {
  return firstText([
    recordField(plugin, "name"),
    recordField(plugin, "title"),
    pluginId(plugin)
  ], "Unnamed plugin")
}

function isInstalled(plugin) {
  if (!isRecord(plugin)) return false
  if (plugin.installed === true) return true
  if (plugin.installed === false) return false
  if (isRecord(plugin.installedEntry)) return true
  if (isRecord(plugin.installation) && plugin.installation.installed === true)
    return true

  var state = lowerString(plugin.installState)
  return state === "installed" || state === "enabled" || state === "disabled"
}

function metadataValue(value, fallback) {
  if (value !== undefined && value !== null && trimmedString(value).length > 0)
    return String(value)
  if (arguments.length >= 2)
    return fallback === undefined || fallback === null ? "" : String(fallback)
  return "Not declared"
}

function pluginVersionText(plugin) {
  if (!isRecord(plugin)) return ""

  var declaredVersion = metadataValue(recordField(plugin, "version"), "Unknown")
  if (!isInstalled(plugin)) return declaredVersion

  var installedVersion = metadataValue(plugin.installedVersion, "")
  if (installedVersion.length > 0 && installedVersion !== declaredVersion)
    return declaredVersion + " (installed " + installedVersion + ")"
  return installedVersion || declaredVersion
}

function normalizeQuery(query) {
  return lowerString(query)
}

function normalizeFilter(filter) {
  if (filter === true) return FILTER_INSTALLED

  var normalized = lowerString(filter)
  if (normalized === FILTER_INSTALLED
      || normalized === "installed-only"
      || normalized === "installed_only") {
    return FILTER_INSTALLED
  }

  return FILTER_ALL
}

function compareStrings(first, second) {
  if (first < second) return -1
  if (first > second) return 1
  return 0
}

function numericRunValue(value) {
  var significant = value.replace(/^0+/, "")
  return significant.length > 0 ? significant : "0"
}

function compareNumericRuns(first, second) {
  var firstValue = numericRunValue(first)
  var secondValue = numericRunValue(second)

  if (firstValue.length !== secondValue.length)
    return firstValue.length < secondValue.length ? -1 : 1

  var valueComparison = compareStrings(firstValue, secondValue)
  if (valueComparison !== 0) return valueComparison

  // Equal numeric values use the shorter representation first: 2, 02, 002.
  if (first.length !== second.length) return first.length < second.length ? -1 : 1
  return compareStrings(first, second)
}

function naturalRuns(value) {
  return stringValue(value).match(/\d+|\D+/g) || []
}

function foldedNaturalCompare(first, second) {
  var firstRuns = naturalRuns(first)
  var secondRuns = naturalRuns(second)
  var count = Math.min(firstRuns.length, secondRuns.length)

  for (var i = 0; i < count; i++) {
    var firstRun = firstRuns[i]
    var secondRun = secondRuns[i]
    var firstIsNumber = /^\d+$/.test(firstRun)
    var secondIsNumber = /^\d+$/.test(secondRun)
    var comparison

    if (firstIsNumber && secondIsNumber) {
      comparison = compareNumericRuns(firstRun, secondRun)
    } else {
      comparison = compareStrings(firstRun.toLowerCase(), secondRun.toLowerCase())
    }

    if (comparison !== 0) return comparison
  }

  if (firstRuns.length !== secondRuns.length)
    return firstRuns.length < secondRuns.length ? -1 : 1
  return 0
}

function naturalCompare(first, second) {
  var firstString = stringValue(first)
  var secondString = stringValue(second)
  var folded = foldedNaturalCompare(firstString, secondString)

  // The raw comparison makes case-only ties deterministic across JS engines.
  return folded !== 0 ? folded : compareStrings(firstString, secondString)
}

function comparePlugins(first, second) {
  var firstUpdated = Number(recordField(first, "updatedAt"))
  var secondUpdated = Number(recordField(second, "updatedAt"))
  if (!isFinite(firstUpdated) || firstUpdated < 0) firstUpdated = 0
  if (!isFinite(secondUpdated) || secondUpdated < 0) secondUpdated = 0
  if (firstUpdated !== secondUpdated)
    return firstUpdated > secondUpdated ? -1 : 1

  var byName = naturalCompare(pluginName(first), pluginName(second))
  if (byName !== 0) return byName
  return naturalCompare(pluginId(first), pluginId(second))
}

function sortPlugins(plugins) {
  if (!Array.isArray(plugins)) return []

  var decorated = []
  for (var i = 0; i < plugins.length; i++) {
    if (!isRecord(plugins[i])) continue
    decorated.push({ index: i, plugin: plugins[i] })
  }

  decorated.sort(function (first, second) {
    var comparison = comparePlugins(first.plugin, second.plugin)
    return comparison !== 0 ? comparison : first.index - second.index
  })

  var sorted = []
  for (var sortedIndex = 0; sortedIndex < decorated.length; sortedIndex++)
    sorted.push(decorated[sortedIndex].plugin)
  return sorted
}

function searchFields(plugin) {
  if (!isRecord(plugin)) return []

  var manifest = isRecord(plugin.manifest) ? plugin.manifest : {}
  return [
    plugin.name,
    plugin.title,
    plugin.description,
    plugin.author,
    manifest.name,
    manifest.title,
    manifest.description,
    manifest.author
  ]
}

function matchesSearch(plugin, query) {
  if (!isRecord(plugin)) return false

  var needle = normalizeQuery(query)
  if (needle.length === 0) return true

  var fields = searchFields(plugin)
  for (var i = 0; i < fields.length; i++) {
    if (stringValue(fields[i]).toLowerCase().indexOf(needle) !== -1) return true
  }
  return false
}

function filterPlugins(plugins, query, filter) {
  if (!Array.isArray(plugins)) return []

  var mode = normalizeFilter(filter)
  var filtered = []
  for (var i = 0; i < plugins.length; i++) {
    var plugin = plugins[i]
    if (!isRecord(plugin)) continue
    if (mode === FILTER_INSTALLED && !isInstalled(plugin)) continue
    if (!matchesSearch(plugin, query)) continue
    filtered.push(plugin)
  }
  return sortPlugins(filtered)
}

function clampedIndex(value, length) {
  if (length <= 0) return -1

  var numeric = Number(value)
  if (!isFinite(numeric)) numeric = 0
  numeric = Math.floor(numeric)
  return Math.max(0, Math.min(length - 1, numeric))
}

function scaleAdjustedWindowSide(styledSide, outputScale, minimumSide) {
  var side = Number(styledSide)
  var scale = Number(outputScale)
  var minimum = Number(minimumSide)

  if (!isFinite(side) || side <= 0) side = 1
  if (!isFinite(scale) || scale < 1) scale = 1
  if (!isFinite(minimum) || minimum < 1) minimum = 1

  return Math.max(Math.round(minimum), Math.round(side / scale))
}

function resolveSelection(plugins, selectedId, previousIndex) {
  var values = Array.isArray(plugins) ? plugins : []
  if (values.length === 0) {
    return {
      id: "",
      index: -1,
      plugin: null
    }
  }

  var requestedId = trimmedString(selectedId)
  if (requestedId.length > 0) {
    for (var i = 0; i < values.length; i++) {
      if (pluginId(values[i]) === requestedId) {
        return {
          id: requestedId,
          index: i,
          plugin: values[i]
        }
      }
    }
  }

  var index = clampedIndex(previousIndex, values.length)
  return {
    id: pluginId(values[index]),
    index: index,
    plugin: values[index]
  }
}

function buildViewModel(plugins, query, filter, selectedId, previousIndex) {
  var visiblePlugins = filterPlugins(plugins, query, filter)
  var selection = resolveSelection(visiblePlugins, selectedId, previousIndex)

  return {
    plugins: visiblePlugins,
    selectedId: selection.id,
    selectedIndex: selection.index,
    selectedPlugin: selection.plugin
  }
}

function screenshotReference(screenshot) {
  if (typeof screenshot === "string") return trimmedString(screenshot)
  if (!isRecord(screenshot)) return ""

  return firstText([
    screenshot.name,
    screenshot.fileName,
    screenshot.path,
    screenshot.source,
    screenshot.url
  ])
}

function screenshotName(screenshot) {
  var reference = screenshotReference(screenshot)
  var clean = reference.split(/[?#]/)[0].replace(/\\/g, "/")
  var parts = clean.split("/")
  return parts.length > 0 ? parts[parts.length - 1] : clean
}

function isSupportedScreenshot(screenshot) {
  var name = screenshotName(screenshot)
  var separator = name.lastIndexOf(".")
  if (separator < 1 || separator === name.length - 1) return false
  return SUPPORTED_SCREENSHOT_EXTENSIONS[name.slice(separator + 1).toLowerCase()] === true
}

function sortScreenshots(screenshots) {
  if (!Array.isArray(screenshots)) return []

  var decorated = []
  for (var i = 0; i < screenshots.length; i++) {
    if (screenshotReference(screenshots[i]).length === 0) continue
    decorated.push({
      index: i,
      name: screenshotName(screenshots[i]),
      reference: screenshotReference(screenshots[i]),
      screenshot: screenshots[i]
    })
  }

  decorated.sort(function (first, second) {
    var comparison = naturalCompare(first.name, second.name)
    if (comparison === 0)
      comparison = naturalCompare(first.reference, second.reference)
    return comparison !== 0 ? comparison : first.index - second.index
  })

  var sorted = []
  for (var sortedIndex = 0; sortedIndex < decorated.length; sortedIndex++)
    sorted.push(decorated[sortedIndex].screenshot)
  return sorted
}

function supportedScreenshots(screenshots) {
  if (!Array.isArray(screenshots)) return []

  var supported = []
  for (var i = 0; i < screenshots.length; i++) {
    if (isSupportedScreenshot(screenshots[i])) supported.push(screenshots[i])
  }
  return sortScreenshots(supported)
}

function copyRecord(record) {
  var copy = {}
  if (!isRecord(record)) return copy

  for (var key in record) {
    if (own(record, key)) copy[key] = record[key]
  }
  return copy
}

function overlayRecord(target, record) {
  if (!isRecord(record)) return target
  for (var key in record) {
    if (own(record, key)) target[key] = record[key]
  }
  return target
}

function indexedById(records, excluded) {
  var index = {}
  if (!Array.isArray(records)) return index

  for (var i = 0; i < records.length; i++) {
    var id = pluginId(records[i])
    var key = "$" + id
    if (id.length === 0 || excluded(id) || own(index, key)) continue
    index[key] = records[i]
  }
  return index
}

function exclusionPredicate(options) {
  options = isRecord(options) ? options : {}
  var excludeFirstParty = options.excludeFirstParty !== false
  var selfId = own(options, "selfId") ? trimmedString(options.selfId) : "b.okomart"
  var excludedIds = {}
  var values = Array.isArray(options.excludeIds) ? options.excludeIds : []

  for (var i = 0; i < values.length; i++) {
    var excluded = trimmedString(values[i])
    if (excluded.length > 0) excludedIds["$" + excluded] = true
  }

  return function (id) {
    if (selfId.length > 0 && id === selfId) return true
    if (excludeFirstParty && id.indexOf("omarchy.") === 0) return true
    return excludedIds["$" + id] === true
  }
}

function normalizedMergedPlugin(base, catalogEntry, installedEntry, removedEntry) {
  var merged = copyRecord(installedEntry)
  overlayRecord(merged, base)

  var id = firstText([
    pluginId(catalogEntry),
    pluginId(installedEntry),
    pluginId(removedEntry),
    pluginId(base)
  ])
  var catalogVersion = trimmedString(recordField(catalogEntry, "version"))
  var installedVersion = trimmedString(recordField(installedEntry, "version"))

  merged.id = id
  merged.name = firstText([
    recordField(base, "name"),
    recordField(installedEntry, "name"),
    id
  ], "Unnamed plugin")
  merged.description = firstText([
    recordField(base, "description"),
    recordField(installedEntry, "description")
  ])
  merged.author = firstText([
    recordField(base, "author"),
    recordField(installedEntry, "author")
  ])
  merged.version = firstText([
    recordField(base, "version"),
    recordField(installedEntry, "version")
  ])
  merged.availableVersion = catalogEntry ? catalogVersion : ""
  merged.installedVersion = installedEntry ? installedVersion : ""
  merged.inCatalog = catalogEntry !== null
  merged.installed = installedEntry !== null
  merged.external = installedEntry !== null
    && catalogEntry === null
    && removedEntry === null
  merged.removed = installedEntry !== null
    && catalogEntry === null
    && removedEntry !== null
  merged.catalogEntry = catalogEntry
  merged.installedEntry = installedEntry
  merged.removedEntry = removedEntry

  return merged
}

function mergePluginSources(catalogPlugins, installedPlugins, removedPlugins, options) {
  var excluded = exclusionPredicate(options)
  var catalog = indexedById(catalogPlugins, excluded)
  var installed = indexedById(installedPlugins, excluded)
  var removed = indexedById(removedPlugins, excluded)
  var result = []
  var key

  for (key in catalog) {
    if (!own(catalog, key)) continue
    var catalogEntry = catalog[key]
    var installedEntry = own(installed, key) ? installed[key] : null
    result.push(normalizedMergedPlugin(
      catalogEntry,
      catalogEntry,
      installedEntry,
      null
    ))
  }

  for (key in installed) {
    if (!own(installed, key) || own(catalog, key)) continue

    var removedEntry = own(removed, key) ? removed[key] : null
    result.push(normalizedMergedPlugin(
      removedEntry || installed[key],
      null,
      installed[key],
      removedEntry
    ))
  }

  return sortPlugins(result)
}

function sourceState(plugin) {
  if (!isRecord(plugin)) return "catalog"
  if (plugin.removed === true) return "removed"
  if (plugin.external === true) return "external"
  if (plugin.inCatalog === false && isInstalled(plugin)) return "external"
  return "catalog"
}

function sourceLabel(plugin) {
  var state = sourceState(plugin)
  if (state === "removed") return "Removed from catalog"
  if (state === "external") return "External install"
  return "Catalog"
}

function clickableSourceUrl(plugin) {
  if (!isRecord(plugin)) return ""

  var source = firstText([
    plugin.installedSourceUrl,
    recordField(plugin, "sourceUrl"),
    recordField(plugin, "originUrl")
  ])
  return /^https?:\/\/\S+$/i.test(source) ? source : ""
}

function selectableUpdates(updates, selfId) {
  var selfRows = []
  var otherRows = []
  var seen = ({})
  var resolvedSelfId = trimmedString(selfId) || "b.okomart"
  if (!Array.isArray(updates)) return otherRows

  for (var i = 0; i < updates.length; i++) {
    var item = updates[i]
    var id = pluginId(item)
    if (!isRecord(item) || item.safeUpdate !== true || !id || seen[id])
      continue
    seen[id] = true
    if (item.self === true || id === resolvedSelfId) selfRows.push(item)
    else otherRows.push(item)
  }
  return selfRows.concat(otherRows)
}

function snapshotConfirmsUpdates(snapshot, exitCode) {
  return isRecord(snapshot)
    && snapshot.ok === true
    && snapshot.cached !== true
    && snapshot.stale !== true
    && Array.isArray(snapshot.plugins)
    && trimmedString(snapshot.snapshotId).length > 0
    && Number(exitCode) === 0
}

function hyprlandColorComponents(raw) {
  var option = raw
  if (typeof raw === "string") {
    try { option = JSON.parse(raw) } catch (e) { return [] }
  }
  if (!isRecord(option)) return []

  var match = trimmedString(option.custom)
    .match(/^(?:0x)?([0-9A-Fa-f]{8})(?:\s|$)/)
  if (!match) return []
  var argb = match[1]
  return [
    parseInt(argb.substr(2, 2), 16),
    parseInt(argb.substr(4, 2), 16),
    parseInt(argb.substr(6, 2), 16),
    parseInt(argb.substr(0, 2), 16)
  ]
}

function normalizedState(value) {
  return lowerString(value)
    .replace(/[\s_]+/g, "-")
    .replace(/-+/g, "-")
}

function hasVersionUpdate(plugin) {
  if (!isRecord(plugin) || !isInstalled(plugin)) return false
  if (own(plugin, "versionUpdateAvailable"))
    return plugin.versionUpdateAvailable === true

  var installedVersion = firstText([
    plugin.installedVersion,
    plugin.currentVersion
  ])
  var availableVersion = firstText([
    plugin.availableVersion,
    plugin.remoteVersion,
    recordField(plugin, "version")
  ])
  if (!installedVersion || !availableVersion) return false
  return foldedNaturalCompare(availableVersion, installedVersion) > 0
}

function updateState(plugin) {
  if (!isRecord(plugin)) return "unknown"

  var update = isRecord(plugin.update) ? plugin.update : {}
  var raw = firstText([
    plugin.updateState,
    plugin.updateStatus,
    update.state,
    update.status
  ])
  var state = normalizedState(raw)

  if (state === "available"
      || state === "update-available"
      || state === "behind"
      || state === "fast-forward"
      || state === "fast-forwardable") {
    return hasVersionUpdate(plugin) ? "available" : "current"
  }
  if (state === "current"
      || state === "up-to-date"
      || state === "uptodate"
      || state === "none") {
    return "current"
  }
  if (state === "dirty" || state === "local-changes") return "dirty"
  if (state === "diverged") return "diverged"
  if (state === "ahead" || state === "locally-ahead") return "ahead"
  if (state === "missing-origin" || state === "no-origin") return "missing-origin"
  if (state === "offline"
      || state === "fetch-failed"
      || state === "fetch-error") {
    return "offline"
  }
  if (state === "blocked" || state === "unavailable") return "blocked"

  if (plugin.updateAvailable === true
      || plugin.hasUpdate === true
      || update.available === true) {
    return hasVersionUpdate(plugin) ? "available" : "current"
  }
  if (plugin.updateAvailable === false
      || plugin.hasUpdate === false
      || update.available === false) {
    return "current"
  }
  return "unknown"
}

function dirtyGitRemovalBlocked(plugin) {
  return isInstalled(plugin)
    && lowerString(plugin.installType) === "git"
    && (plugin.dirty === true || updateState(plugin) === "dirty")
}

function removalBlockReason(plugin) {
  return dirtyGitRemovalBlocked(plugin) ? DIRTY_GIT_REMOVAL_REASON : ""
}

function canRemovePlugin(plugin) {
  return isInstalled(plugin) && removalBlockReason(plugin).length === 0
}

function updateDetailText(plugin) {
  if (!isInstalled(plugin)) return ""

  var removalReason = removalBlockReason(plugin)
  if (removalReason.length > 0) return removalReason

  var state = updateState(plugin)
  if (state === "available") return ""
  if (state === "dirty") return "Update blocked: local changes"
  if (state === "diverged")
    return "Update blocked: local and remote histories diverged"
  if (state === "ahead") return "Installed checkout is ahead of its remote"
  if (state === "missing-origin")
    return "Update unavailable: Git checkout has no origin"
  if (state === "offline") return "Update status unavailable"
  if (state === "blocked") return "Update blocked"
  if (state === "current") return ""

  var raw = normalizedState(plugin.updateState)
  if (raw === "non-git") return "Local plugin; no Git update source"
  if (raw === "development-link")
    return "Development link; updates are managed externally"
  if (raw === "invalid")
    return "Update unavailable: installed manifest is invalid"
  return "Update status unavailable"
}

function hasUpdate(plugin) {
  return hasVersionUpdate(plugin)
}

function updateLabel(plugin) {
  var state = updateState(plugin)
  if (state === "available") return "Update available"
  if (state === "current") return "Up to date"
  if (state === "dirty") return "Update blocked: local changes"
  if (state === "diverged") return "Update blocked: diverged history"
  if (state === "ahead") return "Locally ahead"
  if (state === "missing-origin") return "Update unavailable: no origin"
  if (state === "offline") return "Update check failed"
  if (state === "blocked") return "Update blocked"
  return ""
}

function actionBlockReason(plugin) {
  if (!isRecord(plugin)) return "Plugin data is unavailable"
  if (plugin.valid === false) {
    return firstText([plugin.error, plugin.validationError], "Plugin manifest is invalid")
  }
  if (plugin.actionable === false) {
    return firstText([plugin.actionReason, plugin.error], "This plugin cannot be changed")
  }
  return ""
}

function primaryAction(plugin) {
  if (!isRecord(plugin)) {
    return {
      kind: "unavailable",
      label: "Unavailable",
      enabled: false,
      reason: "Plugin data is unavailable"
    }
  }

  if (plugin.busy === true) {
    return {
      kind: "busy",
      label: "Working…",
      enabled: false,
      reason: ""
    }
  }

  var blocked = actionBlockReason(plugin)
  if (blocked.length > 0) {
    return {
      kind: "unavailable",
      label: "Unavailable",
      enabled: false,
      reason: blocked
    }
  }

  if (isInstalled(plugin)) {
    var removalReason = removalBlockReason(plugin)
    return {
      kind: "uninstall",
      label: "Uninstall",
      enabled: removalReason.length === 0,
      reason: removalReason
    }
  }

  if (sourceState(plugin) !== "catalog") {
    return {
      kind: "unavailable",
      label: "Unavailable",
      enabled: false,
      reason: "Plugin is not available in the catalog"
    }
  }

  return {
    kind: "install",
    label: "Install",
    enabled: true,
    reason: ""
  }
}

function actionLabel(plugin) {
  return primaryAction(plugin).label
}

if (typeof module !== "undefined") {
  module.exports = {
    FILTER_ALL: FILTER_ALL,
    FILTER_INSTALLED: FILTER_INSTALLED,
    actionLabel: actionLabel,
    buildViewModel: buildViewModel,
    canRemovePlugin: canRemovePlugin,
    clickableSourceUrl: clickableSourceUrl,
    comparePlugins: comparePlugins,
    filterPlugins: filterPlugins,
    hasUpdate: hasUpdate,
    hasVersionUpdate: hasVersionUpdate,
    hyprlandColorComponents: hyprlandColorComponents,
    isInstalled: isInstalled,
    isSupportedScreenshot: isSupportedScreenshot,
    matchesSearch: matchesSearch,
    metadataValue: metadataValue,
    mergePluginSources: mergePluginSources,
    naturalCompare: naturalCompare,
    normalizeFilter: normalizeFilter,
    normalizeQuery: normalizeQuery,
    pluginId: pluginId,
    pluginName: pluginName,
    pluginVersionText: pluginVersionText,
    primaryAction: primaryAction,
    removalBlockReason: removalBlockReason,
    resolveSelection: resolveSelection,
    scaleAdjustedWindowSide: scaleAdjustedWindowSide,
    selectableUpdates: selectableUpdates,
    sortPlugins: sortPlugins,
    sortScreenshots: sortScreenshots,
    snapshotConfirmsUpdates: snapshotConfirmsUpdates,
    sourceLabel: sourceLabel,
    sourceState: sourceState,
    supportedScreenshots: supportedScreenshots,
    updateDetailText: updateDetailText,
    updateLabel: updateLabel,
    updateState: updateState
  }
}
