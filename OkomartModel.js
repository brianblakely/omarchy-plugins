var DIRTY_GIT_REMOVAL_REASON =
  "Uninstall is disabled while this Git checkout has local changes. Commit, stash, or discard them first."

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function stringValue(value) {
  return value === undefined || value === null ? "" : String(value)
}

function trimmedString(value) {
  return stringValue(value).trim()
}

function pluginId(plugin) {
  return isRecord(plugin) ? trimmedString(plugin.id) : ""
}

function isInstalled(plugin) {
  return isRecord(plugin) && plugin.installed === true
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

  var declaredVersion = metadataValue(plugin.version, "Unknown")
  if (!isInstalled(plugin)) return declaredVersion

  var installedVersion = metadataValue(plugin.installedVersion, "")
  if (installedVersion.length > 0 && installedVersion !== declaredVersion)
    return declaredVersion + " (installed " + installedVersion + ")"
  return installedVersion || declaredVersion
}

function matchesSearch(plugin, query) {
  if (!isRecord(plugin)) return false

  var needle = trimmedString(query).toLowerCase()
  if (needle.length === 0) return true

  var fields = [plugin.name, plugin.description, plugin.author]
  for (var i = 0; i < fields.length; i++) {
    if (stringValue(fields[i]).toLowerCase().indexOf(needle) !== -1)
      return true
  }
  return false
}

function filterPlugins(plugins, query, installedOnly) {
  if (!Array.isArray(plugins)) return []

  var filtered = []
  for (var i = 0; i < plugins.length; i++) {
    var plugin = plugins[i]
    if (!isRecord(plugin)) continue
    if (installedOnly === true && !isInstalled(plugin)) continue
    if (matchesSearch(plugin, query)) filtered.push(plugin)
  }
  return filtered
}

function dpiCompactionScale(availableWidth, wideBreakpoint, outputScale) {
  var width = Number(availableWidth)
  var breakpoint = Number(wideBreakpoint)
  var scale = Number(outputScale)

  if (!isFinite(width) || width <= 0
      || !isFinite(breakpoint) || breakpoint <= 0) return 1
  if (!isFinite(scale) || scale < 1) scale = 1
  if (scale === 1 || width >= breakpoint) return 1

  return Math.max(1 / scale, Math.min(1, width / breakpoint))
}

function resolveSelection(plugins, selectedId) {
  var values = Array.isArray(plugins) ? plugins : []
  if (values.length === 0) return ""

  var requestedId = trimmedString(selectedId)
  for (var i = 0; i < values.length; i++) {
    if (pluginId(values[i]) === requestedId) return requestedId
  }
  return pluginId(values[0])
}

function clickableSourceUrl(plugin) {
  if (!isRecord(plugin)) return ""

  var source = trimmedString(plugin.installedSourceUrl)
  if (source.length === 0) source = trimmedString(plugin.sourceUrl)
  return /^https?:\/\/\S+$/i.test(source) ? source : ""
}

function selectableUpdates(updates, selfId) {
  var selfRows = []
  var otherRows = []
  var seen = ({})
  var resolvedSelfId = trimmedString(selfId)
  if (!Array.isArray(updates)) return otherRows

  for (var i = 0; i < updates.length; i++) {
    var item = updates[i]
    var id = pluginId(item)
    if (!isRecord(item) || item.safeUpdate !== true || !id || seen[id])
      continue
    seen[id] = true
    if (id === resolvedSelfId) selfRows.push(item)
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

function copyRecord(record) {
  var copy = {}
  if (!isRecord(record)) return copy
  for (var key in record) copy[key] = record[key]
  return copy
}

function reconciledInstalledPlugin(plugin, operation) {
  var next = copyRecord(plugin)
  if (operation === "install") {
    next.installed = true
    next.installedVersion = metadataValue(next.version, "")
    next.installedSourceUrl = metadataValue(next.sourceUrl, "")
    next.installType = "git"
    next.availableVersion = metadataValue(next.version, "")
    if (trimmedString(next.catalogCommit).length > 0) {
      next.currentCommit = String(next.catalogCommit)
      next.availableCommit = String(next.catalogCommit)
    }
  } else if (operation === "update") {
    next.installed = true
    next.installedVersion = metadataValue(next.availableVersion,
      metadataValue(next.version, metadataValue(next.installedVersion, "")))
    if (trimmedString(next.availableCommit).length > 0)
      next.currentCommit = String(next.availableCommit)
  }
  next.updateState = "up-to-date"
  next.statusText = "Up to date"
  next.versionUpdateAvailable = false
  next.safeUpdate = false
  next.dirty = false
  return next
}

function reconciledRemovedPlugin(plugin) {
  if (plugin.catalog !== true) return null

  var next = copyRecord(plugin)
  next.installed = false
  next.versionUpdateAvailable = false
  next.safeUpdate = false
  var installedFields = [
    "installedVersion", "installedPath", "installedSourceUrl", "installType",
    "updateState", "statusText", "currentCommit", "availableCommit",
    "availableVersion", "dirty", "validationError"
  ]
  for (var i = 0; i < installedFields.length; i++) delete next[installedFields[i]]
  return next
}

function reconcileActionSnapshot(snapshot, results, selfId) {
  if (!isRecord(snapshot) || !Array.isArray(snapshot.plugins)) return snapshot

  var actions = {}
  var values = Array.isArray(results) ? results : []
  for (var i = 0; i < values.length; i++) {
    var result = values[i]
    var id = pluginId(result)
    var operation = isRecord(result) ? trimmedString(result.operation) : ""
    if (result && result.ok === true && id.length > 0
        && (operation === "install" || operation === "remove"
          || operation === "update"))
      actions["$" + id] = operation
  }

  var next = copyRecord(snapshot)
  var plugins = []
  for (var pluginIndex = 0; pluginIndex < snapshot.plugins.length; pluginIndex++) {
    var plugin = snapshot.plugins[pluginIndex]
    if (!isRecord(plugin)) continue
    var action = actions["$" + pluginId(plugin)] || ""
    if (action === "remove") {
      var remaining = reconciledRemovedPlugin(plugin)
      if (remaining !== null) plugins.push(remaining)
    } else if (action === "install" || action === "update") {
      plugins.push(reconciledInstalledPlugin(plugin, action))
    } else {
      plugins.push(plugin)
    }
  }
  next.plugins = plugins

  var resolvedSelfId = trimmedString(selfId)
  if (resolvedSelfId.length > 0 && actions["$" + resolvedSelfId] === "update"
      && isRecord(snapshot.self))
    next.self = reconciledInstalledPlugin(snapshot.self, "update")
  return next
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

function updateState(plugin) {
  if (!isRecord(plugin)) return "unknown"

  var state = trimmedString(plugin.updateState)
  if (state === "update-available") return "available"
  if (state === "up-to-date") return "current"
  if (state === "dirty") return "dirty"
  if (state === "diverged") return "diverged"
  if (state === "ahead") return "ahead"
  if (state === "no-origin") return "missing-origin"
  if (state === "fetch-failed") return "offline"
  return "unknown"
}

function dirtyGitRemovalBlocked(plugin) {
  return isInstalled(plugin)
    && plugin.installType === "git"
    && plugin.dirty === true
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
  if (state === "available" || state === "current") return ""
  if (state === "diverged")
    return "Update blocked: local and remote histories diverged"
  if (state === "ahead") return "Installed checkout is ahead of its remote"
  if (state === "missing-origin")
    return "Update unavailable: Git checkout has no origin"
  if (state === "offline") return "Update status unavailable"

  var raw = trimmedString(plugin.updateState)
  if (raw === "non-git") return "Local plugin; no Git update source"
  if (raw === "development-link")
    return "Development link; updates are managed externally"
  if (raw === "invalid")
    return "Update unavailable: installed manifest is invalid"
  return "Update status unavailable"
}
