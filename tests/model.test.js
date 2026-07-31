const assert = require("node:assert/strict")
const {
  FILTER_ALL,
  FILTER_INSTALLED,
  actionLabel,
  buildViewModel,
  canRemovePlugin,
  clickableSourceUrl,
  filterPlugins,
  hasUpdate,
  hasVersionUpdate,
  isInstalled,
  isSupportedScreenshot,
  matchesSearch,
  metadataValue,
  mergePluginSources,
  naturalCompare,
  normalizeFilter,
  normalizeQuery,
  pluginId,
  pluginName,
  pluginVersionText,
  primaryAction,
  removalBlockReason,
  resolveSelection,
  sortPlugins,
  sortScreenshots,
  sourceLabel,
  sourceState,
  supportedScreenshots,
  updateDetailText,
  updateLabel,
  updateState
} = require("../OkomartModel.js")

let passed = 0

function test(name, callback) {
  callback()
  passed += 1
  process.stdout.write(`ok ${passed} - ${name}\n`)
}

function plugin(overrides = {}) {
  return Object.assign({
    id: "b.example",
    name: "Example",
    description: "An example plugin",
    author: "Brian",
    version: "1.0.0",
    installed: false
  }, overrides)
}

test("exports canonical filter values and normalizes filter input", () => {
  assert.equal(FILTER_ALL, "all")
  assert.equal(FILTER_INSTALLED, "installed")
  assert.equal(normalizeFilter(" Installed "), FILTER_INSTALLED)
  assert.equal(normalizeFilter("installed_only"), FILTER_INSTALLED)
  assert.equal(normalizeFilter(true), FILTER_INSTALLED)
  assert.equal(normalizeFilter("all"), FILTER_ALL)
  assert.equal(normalizeFilter("unexpected"), FILTER_ALL)
  assert.equal(normalizeFilter(null), FILTER_ALL)
})

test("normalizes a search query by trimming and folding case", () => {
  assert.equal(normalizeQuery("  OmaHUD  "), "omahud")
  assert.equal(normalizeQuery(null), "")
  assert.equal(normalizeQuery(42), "42")
})

test("searches name, title, description, and author as case-insensitive substrings", () => {
  const item = plugin({
    name: "OmaHUD",
    title: "Workspace Navigator",
    description: "A discreet Hyprland indicator",
    author: "Brian Blakely"
  })

  assert.equal(matchesSearch(item, " mah "), true)
  assert.equal(matchesSearch(item, "NAVIG"), true)
  assert.equal(matchesSearch(item, "land indi"), true)
  assert.equal(matchesSearch(item, "blake"), true)
  assert.equal(matchesSearch(item, "missing"), false)
})

test("searches fields nested in a manifest and treats blank queries as matches", () => {
  const item = {
    manifest: {
      id: "b.nested",
      name: "Nested Name",
      title: "Nested Title",
      description: "Nested Description",
      author: "Nested Author"
    }
  }

  assert.equal(pluginId(item), "b.nested")
  assert.equal(pluginName(item), "Nested Name")
  assert.equal(matchesSearch(item, "title"), true)
  assert.equal(matchesSearch(item, "DESCRIPTION"), true)
  assert.equal(matchesSearch(item, " author "), true)
  assert.equal(matchesSearch(item, "   "), true)
  assert.equal(matchesSearch(null, ""), false)
})

test("does not accidentally trim searchable field contents into a false match", () => {
  const item = plugin({ name: "A  B", description: "", author: "" })
  assert.equal(matchesSearch(item, "a  b"), true)
  assert.equal(matchesSearch(item, "a b"), false)
})

test("recognizes explicit and structured installed state", () => {
  assert.equal(isInstalled(plugin({ installed: true })), true)
  assert.equal(isInstalled(plugin({ installed: false, installedEntry: {} })), false)
  assert.equal(isInstalled({ installedEntry: { path: "/tmp/plugin" } }), true)
  assert.equal(isInstalled({ installation: { installed: true } }), true)
  assert.equal(isInstalled({ installState: " Enabled " }), true)
  assert.equal(isInstalled({ installState: "disabled" }), true)
  assert.equal(isInstalled({ installState: "available" }), false)
  assert.equal(isInstalled(null), false)
})

test("preserves explicit metadata fallbacks and scalar values", () => {
  assert.equal(metadataValue(undefined), "Not declared")
  assert.equal(metadataValue(null), "Not declared")
  assert.equal(metadataValue("   "), "Not declared")
  assert.equal(metadataValue("", ""), "")
  assert.equal(metadataValue(null, "Unknown"), "Unknown")
  assert.equal(metadataValue("", 0), "0")
  assert.equal(metadataValue("", false), "false")
  assert.equal(metadataValue(0), "0")
  assert.equal(metadataValue(false), "false")
})

test("exposes only browser-safe plugin source URLs", () => {
  assert.equal(clickableSourceUrl(plugin({
    installedSourceUrl: " https://github.com/example/installed.git ",
    sourceUrl: "https://github.com/example/catalog.git"
  })), "https://github.com/example/installed.git")
  assert.equal(clickableSourceUrl(plugin({
    sourceUrl: "https://github.com/example/catalog.git"
  })), "https://github.com/example/catalog.git")
  assert.equal(clickableSourceUrl({
    manifest: { originUrl: "http://example.test/plugin.git" }
  }), "http://example.test/plugin.git")
  assert.equal(clickableSourceUrl(plugin({
    sourceUrl: "git@github.com:example/plugin.git"
  })), "")
  assert.equal(clickableSourceUrl(plugin({
    sourceUrl: "file:///tmp/plugin"
  })), "")
  assert.equal(clickableSourceUrl(plugin({
    sourceUrl: "javascript:alert(1)"
  })), "")
  assert.equal(clickableSourceUrl(null), "")
})

test("renders catalog and installed versions without a phantom fallback", () => {
  assert.equal(pluginVersionText(plugin({
    installed: false,
    version: "1.0",
    installedVersion: ""
  })), "1.0")
  assert.equal(pluginVersionText(plugin({
    installed: false,
    version: "2.0",
    installedVersion: "1.0"
  })), "2.0")
  assert.equal(pluginVersionText(plugin({
    installed: false,
    version: ""
  })), "Unknown")
  assert.equal(pluginVersionText(plugin({
    installed: true,
    version: "2.0",
    installedVersion: "1.0"
  })), "2.0 (installed 1.0)")
  assert.equal(pluginVersionText(plugin({
    installed: true,
    version: "1.0",
    installedVersion: ""
  })), "1.0")
  assert.equal(pluginVersionText(null), "")
})

test("compares natural numeric runs without numeric overflow", () => {
  const values = [
    "Plugin 10",
    "plugin 2",
    "plugin 0002",
    "Plugin 02",
    "plugin 999999999999999999999999",
    "plugin 20"
  ]

  values.sort(naturalCompare)
  assert.deepEqual(values, [
    "plugin 2",
    "Plugin 02",
    "plugin 0002",
    "Plugin 10",
    "plugin 20",
    "plugin 999999999999999999999999"
  ])
})

test("uses raw code-unit order only after case-insensitive natural equality", () => {
  assert.ok(naturalCompare("A10", "a2") > 0)
  assert.ok(naturalCompare("Alpha", "alpha") < 0)
  assert.equal(naturalCompare("same", "same"), 0)
})

test("sorts timestamp ties naturally by display name and id without mutation", () => {
  const input = [
    plugin({ id: "b.z", name: "Tool 10" }),
    plugin({ id: "b.second", name: "Tool 2" }),
    plugin({ id: "b.first", name: "Tool 2" }),
    plugin({ id: "b.one", name: "Tool 1" })
  ]
  const snapshot = input.slice()
  const sorted = sortPlugins(input)

  assert.deepEqual(sorted.map(item => item.id), [
    "b.one",
    "b.first",
    "b.second",
    "b.z"
  ])
  assert.deepEqual(input, snapshot)
  assert.notEqual(sorted, input)
})

test("sorts plugins by most recent repository update first", () => {
  const input = [
    plugin({ id: "b.old", name: "A", updatedAt: 100 }),
    plugin({ id: "b.new", name: "Z", updatedAt: 300 }),
    plugin({ id: "b.unknown", name: "B", updatedAt: "" }),
    plugin({ id: "b.middle", name: "C", updatedAt: 200 })
  ]

  assert.deepEqual(sortPlugins(input).map(item => item.id), [
    "b.new",
    "b.middle",
    "b.old",
    "b.unknown"
  ])
})

test("uses title then id then a safe placeholder when a name is absent", () => {
  assert.equal(pluginName({ id: "b.id", title: "Title" }), "Title")
  assert.equal(pluginName({ id: "b.id" }), "b.id")
  assert.equal(pluginName({}), "Unnamed plugin")
  assert.equal(pluginName(null), "Unnamed plugin")
})

test("combines installed filtering, search, and natural ordering", () => {
  const plugins = [
    plugin({ id: "b.ten", name: "Tool 10", installed: true }),
    plugin({ id: "b.two", name: "Tool 2", installed: false }),
    plugin({
      id: "b.author",
      name: "Other",
      author: "Toolsmith",
      installed: true
    }),
    null
  ]

  assert.deepEqual(
    filterPlugins(plugins, "tool", "installed").map(item => item.id),
    ["b.author", "b.ten"]
  )
  assert.deepEqual(
    filterPlugins(plugins, "", "all").map(item => item.id),
    ["b.author", "b.two", "b.ten"]
  )
  assert.deepEqual(filterPlugins(null, "", "all"), [])
})

test("preserves selection by id when sorting changes its index", () => {
  const visible = sortPlugins([
    plugin({ id: "b.three", name: "Three" }),
    plugin({ id: "b.one", name: "One" }),
    plugin({ id: "b.two", name: "Two" })
  ])
  const selection = resolveSelection(visible, "b.two", 0)

  assert.equal(selection.id, "b.two")
  assert.equal(selection.index, 2)
  assert.equal(selection.plugin.id, "b.two")
})

test("clamps the prior index when the selected id leaves the view", () => {
  const visible = [
    plugin({ id: "b.one", name: "One" }),
    plugin({ id: "b.two", name: "Two" })
  ]

  assert.deepEqual(resolveSelection(visible, "b.gone", 99), {
    id: "b.two",
    index: 1,
    plugin: visible[1]
  })
  assert.equal(resolveSelection(visible, "", -4).index, 0)
  assert.equal(resolveSelection(visible, "", Number.NaN).index, 0)
  assert.deepEqual(resolveSelection([], "b.gone", 2), {
    id: "",
    index: -1,
    plugin: null
  })
})

test("builds an immutable visible model and reconciles selection", () => {
  const input = [
    plugin({ id: "b.ten", name: "Item 10", installed: true }),
    plugin({ id: "b.two", name: "Item 2", installed: true }),
    plugin({ id: "b.hidden", name: "Hidden", installed: false })
  ]
  const view = buildViewModel(input, "item", "installed", "b.ten", 0)

  assert.deepEqual(view.plugins.map(item => item.id), ["b.two", "b.ten"])
  assert.equal(view.selectedId, "b.ten")
  assert.equal(view.selectedIndex, 1)
  assert.equal(view.selectedPlugin.id, "b.ten")
  assert.deepEqual(input.map(item => item.id), ["b.ten", "b.two", "b.hidden"])
})

test("sorts screenshot basenames naturally and preserves values and input", () => {
  const object = { path: "/cache/shot2.png", caption: "Second" }
  const input = [
    "/cache/shot10.png",
    object,
    "/other/shot1.png",
    "/cache/shot02.png?revision=abc",
    "",
    null
  ]
  const snapshot = input.slice()
  const sorted = sortScreenshots(input)

  assert.deepEqual(sorted, [
    "/other/shot1.png",
    object,
    "/cache/shot02.png?revision=abc",
    "/cache/shot10.png"
  ])
  assert.deepEqual(input, snapshot)
})

test("recognizes supported screenshot extensions case-insensitively", () => {
  for (const extension of ["jpg", "jpeg", "png", "gif", "bmp", "webp"]) {
    assert.equal(isSupportedScreenshot(`image.${extension}`), true)
    assert.equal(isSupportedScreenshot(`image.${extension.toUpperCase()}?v=2`), true)
  }
  assert.equal(isSupportedScreenshot(".png"), false)
  assert.equal(isSupportedScreenshot("image.svg"), false)
  assert.equal(isSupportedScreenshot("image.png.txt"), false)
  assert.equal(isSupportedScreenshot(null), false)
})

test("filters unsupported screenshots before natural sorting", () => {
  const values = [
    "image10.webp",
    "notes.txt",
    { fileName: "image2.PNG" },
    { source: "file:///tmp/image1.jpg#revision" },
    {}
  ]

  assert.deepEqual(supportedScreenshots(values), [
    { source: "file:///tmp/image1.jpg#revision" },
    { fileName: "image2.PNG" },
    "image10.webp"
  ])
})

test("merges catalog and installed records while retaining catalog metadata", () => {
  const catalog = [
    plugin({
      id: "b.alpha",
      name: "Alpha Catalog",
      version: "2.0.0",
      installed: undefined,
      url: "https://example.test/alpha"
    }),
    plugin({
      id: "b.beta",
      name: "Beta",
      version: "1.0.0",
      installed: undefined
    })
  ]
  const installed = [
    plugin({
      id: "b.alpha",
      name: "Old Alpha",
      version: "1.0.0",
      installed: undefined,
      updateState: "available",
      path: "/plugins/b.alpha"
    })
  ]
  const merged = mergePluginSources(catalog, installed, [])
  const alpha = merged.find(item => item.id === "b.alpha")
  const beta = merged.find(item => item.id === "b.beta")

  assert.equal(alpha.name, "Alpha Catalog")
  assert.equal(alpha.version, "2.0.0")
  assert.equal(alpha.availableVersion, "2.0.0")
  assert.equal(alpha.installedVersion, "1.0.0")
  assert.equal(alpha.installed, true)
  assert.equal(alpha.inCatalog, true)
  assert.equal(alpha.external, false)
  assert.equal(alpha.removed, false)
  assert.equal(alpha.updateState, "available")
  assert.equal(alpha.path, "/plugins/b.alpha")
  assert.equal(beta.installed, false)
  assert.equal(beta.installedEntry, null)
  assert.equal(beta.inCatalog, true)
})

test("classifies unmatched installs as external and removed matches as tombstones", () => {
  const installed = [
    plugin({ id: "b.external", name: "External", installed: undefined }),
    plugin({ id: "b.removed", name: "Installed Copy", installed: undefined })
  ]
  const previousCatalog = [
    plugin({
      id: "b.removed",
      name: "Removed Catalog Name",
      description: "No longer published",
      version: "3.0.0",
      installed: undefined
    }),
    plugin({ id: "b.not-installed", installed: undefined })
  ]
  const merged = mergePluginSources([], installed, previousCatalog)
  const external = merged.find(item => item.id === "b.external")
  const removed = merged.find(item => item.id === "b.removed")

  assert.deepEqual(merged.map(item => item.id), ["b.external", "b.removed"])
  assert.equal(external.external, true)
  assert.equal(external.removed, false)
  assert.equal(sourceState(external), "external")
  assert.equal(sourceLabel(external), "External install")
  assert.equal(removed.name, "Removed Catalog Name")
  assert.equal(removed.external, false)
  assert.equal(removed.removed, true)
  assert.equal(removed.inCatalog, false)
  assert.equal(removed.availableVersion, "")
  assert.equal(sourceState(removed), "removed")
  assert.equal(sourceLabel(removed), "Removed from catalog")
})

test("does not retain removed catalog entries unless they remain installed", () => {
  const merged = mergePluginSources(
    [plugin({ id: "b.current", installed: undefined })],
    [],
    [plugin({ id: "b.old", installed: undefined })]
  )

  assert.deepEqual(merged.map(item => item.id), ["b.current"])
})

test("excludes Okomart, first-party plugins, invalid ids, and duplicate source ids", () => {
  const merged = mergePluginSources([
    plugin({ id: "b.okomart", name: "Okomart", installed: undefined }),
    plugin({ id: "omarchy.bar", name: "Bar", installed: undefined }),
    plugin({ id: "", name: "Invalid", installed: undefined }),
    plugin({ id: "b.keep", name: "First", installed: undefined }),
    plugin({ id: "b.keep", name: "Duplicate", installed: undefined })
  ], [], [])

  assert.deepEqual(merged.map(item => item.id), ["b.keep"])
  assert.equal(merged[0].name, "First")
})

test("allows callers to include first-party and alternate self ids explicitly", () => {
  const merged = mergePluginSources([
    plugin({ id: "b.okomart", installed: undefined }),
    plugin({ id: "omarchy.bar", installed: undefined })
  ], [], [], {
    excludeFirstParty: false,
    selfId: ""
  })

  assert.deepEqual(merged.map(item => item.id), ["b.okomart", "omarchy.bar"])
})

test("does not mutate any source record or array during a merge", () => {
  const catalogItem = plugin({
    id: "b.copy",
    installed: undefined,
    manifest: { id: "b.copy", name: "Nested" }
  })
  const installedItem = plugin({
    id: "b.copy",
    installed: undefined,
    path: "/plugins/copy"
  })
  const catalog = [catalogItem]
  const installed = [installedItem]
  const merged = mergePluginSources(catalog, installed, [])

  assert.notEqual(merged[0], catalogItem)
  assert.notEqual(merged[0], installedItem)
  assert.equal(catalogItem.inCatalog, undefined)
  assert.equal(installedItem.inCatalog, undefined)
  assert.deepEqual(catalog, [catalogItem])
  assert.deepEqual(installed, [installedItem])
})

test("normalizes update states and labels safe, blocked, and unavailable cases", () => {
  const cases = [
    [{
      installed: true,
      installedVersion: "1.0.0",
      availableVersion: "2.0.0",
      updateState: "update-available"
    }, "available", "Update available"],
    [{
      installed: true,
      installedVersion: "1.0.0",
      availableVersion: "2.0.0",
      updateState: "fast_forward"
    }, "available", "Update available"],
    [{ updateState: "up-to-date" }, "current", "Up to date"],
    [{ updateStatus: "up to date" }, "current", "Up to date"],
    [{ update: { state: "local changes" } }, "dirty", "Update blocked: local changes"],
    [{ updateState: "diverged" }, "diverged", "Update blocked: diverged history"],
    [{ updateState: "locally_ahead" }, "ahead", "Locally ahead"],
    [{ updateState: "no origin" }, "missing-origin", "Update unavailable: no origin"],
    [{ updateState: "fetch-failed" }, "offline", "Update check failed"],
    [{ updateState: "fetch failed" }, "offline", "Update check failed"],
    [{ updateState: "blocked" }, "blocked", "Update blocked"],
    [{}, "unknown", ""]
  ]

  for (const [item, state, label] of cases) {
    assert.equal(updateState(item), state)
    assert.equal(updateLabel(item), label)
  }
})

test("requires a higher manifest version before exposing an update", () => {
  const newer = {
    installed: true,
    installedVersion: "1.9.0",
    availableVersion: "1.10.0"
  }
  assert.equal(hasVersionUpdate(newer), true)
  assert.equal(hasVersionUpdate(Object.assign({}, newer, {
    availableVersion: "1.9.0"
  })), false)
  assert.equal(hasVersionUpdate(Object.assign({}, newer, {
    availableVersion: "1.8.9"
  })), false)
  assert.equal(hasVersionUpdate(Object.assign({}, newer, {
    versionUpdateAvailable: false
  })), false)
  assert.equal(hasVersionUpdate({ installed: true, availableVersion: "2.0.0" }), false)
  assert.equal(updateState(Object.assign({}, newer, {
    updateState: "update-available"
  })), "available")
  assert.equal(updateState(Object.assign({}, newer, {
    availableVersion: "1.9.0",
    updateState: "update-available"
  })), "current")
})

test("uses explicit update booleans only when a higher version exists", () => {
  const versions = {
    installed: true,
    installedVersion: "1.0.0",
    availableVersion: "2.0.0"
  }
  assert.equal(updateState(Object.assign({}, versions, {
    updateAvailable: true
  })), "available")
  assert.equal(updateState({ hasUpdate: false }), "current")
  assert.equal(updateState(Object.assign({}, versions, {
    update: { available: true }
  })), "available")
  assert.equal(hasUpdate(Object.assign({}, versions, {
    updateState: "available"
  })), true)
  assert.equal(hasUpdate(Object.assign({}, versions, {
    updateState: "dirty",
    updateAvailable: true
  })), true)
  assert.equal(hasUpdate({ updateState: "current" }), false)
  assert.equal(hasUpdate(null), false)
})

test("omits update detail for every uninstalled state", () => {
  const states = [
    "update-available",
    "up-to-date",
    "dirty",
    "diverged",
    "ahead",
    "no-origin",
    "fetch-failed",
    "blocked",
    "non-git",
    "development-link",
    "invalid"
  ]

  for (const state of states) {
    const item = plugin({
      installed: false,
      updateState: state,
      availableVersion: "2.0"
    })
    assert.equal(updateDetailText(item), "")
  }
})

test("shows only actionable or exceptional update detail for installed plugins", () => {
  const cases = [
    [{
      updateState: "update-available",
      installedVersion: "1.0",
      availableVersion: "2.0"
    },
      "Update available: 2.0"],
    [{ updateState: "update-available", availableVersion: "" },
      ""],
    [{ updateState: "up-to-date" }, ""],
    [{ updateState: "diverged" },
      "Update blocked: local and remote histories diverged"],
    [{ updateState: "ahead" }, "Installed checkout is ahead of its remote"],
    [{ updateState: "no-origin" },
      "Update unavailable: Git checkout has no origin"],
    [{ updateState: "fetch-failed" }, "Update status unavailable"],
    [{ updateState: "blocked" }, "Update blocked"],
    [{ updateState: "non-git" }, "Local plugin; no Git update source"],
    [{ updateState: "development-link" },
      "Development link; updates are managed externally"],
    [{ updateState: "invalid" },
      "Update unavailable: installed manifest is invalid"],
    [{ updateState: "" }, "Update status unavailable"]
  ]

  for (const [overrides, expected] of cases)
    assert.equal(updateDetailText(plugin(Object.assign({ installed: true }, overrides))), expected)

  const dirtyGit = plugin({
    installed: true,
    installType: "git",
    dirty: true,
    updateState: "dirty"
  })
  assert.equal(updateDetailText(dirtyGit), removalBlockReason(dirtyGit))
})

test("blocks only dirty Git checkouts from removal", () => {
  const dirtyGit = plugin({
    installed: true,
    installType: "git",
    dirty: true,
    updateState: "invalid"
  })
  const dirtyStateGit = plugin({
    installed: true,
    installType: "git",
    dirty: false,
    updateState: "dirty"
  })
  const removable = [
    plugin({
      installed: true,
      installType: "git",
      dirty: false,
      updateState: "up-to-date"
    }),
    plugin({
      installed: true,
      installType: "git",
      dirty: false,
      updateState: "ahead"
    }),
    plugin({
      installed: true,
      installType: "git",
      dirty: false,
      updateState: "diverged"
    }),
    plugin({
      installed: true,
      installType: "local",
      dirty: true,
      updateState: "dirty"
    }),
    plugin({
      installed: true,
      installType: "development-link",
      dirty: true,
      updateState: "development-link"
    })
  ]

  for (const item of [dirtyGit, dirtyStateGit]) {
    assert.equal(canRemovePlugin(item), false)
    assert.match(removalBlockReason(item), /local changes/)
    assert.equal(updateDetailText(item), removalBlockReason(item))
    assert.deepEqual(primaryAction(item), {
      kind: "uninstall",
      label: "Uninstall",
      enabled: false,
      reason: removalBlockReason(item)
    })
  }
  for (const item of removable) {
    assert.equal(canRemovePlugin(item), true)
    assert.equal(removalBlockReason(item), "")
    assert.equal(primaryAction(item).enabled, true)
  }
  assert.equal(canRemovePlugin(plugin({ installed: false })), false)
  assert.equal(removalBlockReason(plugin({
    installed: false,
    installType: "git",
    dirty: true
  })), "")
})

test("provides install, uninstall, busy, invalid, and unavailable actions", () => {
  assert.deepEqual(primaryAction(plugin()), {
    kind: "install",
    label: "Install",
    enabled: true,
    reason: ""
  })
  assert.equal(actionLabel(plugin({ installed: true })), "Uninstall")
  assert.deepEqual(primaryAction(plugin({ busy: true })), {
    kind: "busy",
    label: "Working…",
    enabled: false,
    reason: ""
  })
  assert.deepEqual(primaryAction(plugin({
    valid: false,
    error: "Bad manifest"
  })), {
    kind: "unavailable",
    label: "Unavailable",
    enabled: false,
    reason: "Bad manifest"
  })
  assert.deepEqual(primaryAction({
    id: "b.external",
    installed: false,
    external: true
  }), {
    kind: "unavailable",
    label: "Unavailable",
    enabled: false,
    reason: "Plugin is not available in the catalog"
  })
  assert.equal(primaryAction(null).enabled, false)
})

process.stdout.write(`${passed} Okomart model tests passed\n`)
