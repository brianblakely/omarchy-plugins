const assert = require("node:assert/strict")
const { readFileSync } = require("node:fs")
const { resolve } = require("node:path")
const vm = require("node:vm")

const modelPath = resolve(__dirname, "..", "OkomartModel.js")
const modelNames = [
  "canRemovePlugin",
  "clickableSourceUrl",
  "dpiCompactionScale",
  "filterPlugins",
  "hyprlandColorComponents",
  "metadataValue",
  "pluginVersionText",
  "reconcileActionSnapshot",
  "removalBlockReason",
  "resolveSelection",
  "selectableUpdates",
  "snapshotConfirmsUpdates",
  "updateDetailText",
  "updateState"
]
const model = vm.runInNewContext(
  readFileSync(modelPath, "utf8")
    + "\n({" + modelNames.join(",") + "})",
  {},
  { filename: modelPath }
)
const {
  canRemovePlugin,
  clickableSourceUrl,
  dpiCompactionScale,
  filterPlugins,
  hyprlandColorComponents,
  metadataValue,
  pluginVersionText,
  reconcileActionSnapshot,
  removalBlockReason,
  resolveSelection,
  selectableUpdates,
  snapshotConfirmsUpdates,
  updateDetailText,
  updateState
} = model

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
    installed: false,
    installedVersion: "",
    availableVersion: "1.0.0",
    versionUpdateAvailable: false,
    updateState: "not-installed",
    safeUpdate: false,
    installType: "none",
    dirty: false
  }, overrides)
}

test("preserves explicit metadata fallbacks and scalar values", () => {
  assert.equal(metadataValue(undefined), "Not declared")
  assert.equal(metadataValue("", "Unknown"), "Unknown")
  assert.equal(metadataValue("", 0), "0")
  assert.equal(metadataValue(false), "false")
})

test("exposes only browser-safe runtime source URLs", () => {
  assert.equal(clickableSourceUrl(plugin({
    installedSourceUrl: " https://github.com/example/installed.git ",
    sourceUrl: "https://github.com/example/catalog.git"
  })), "https://github.com/example/installed.git")
  assert.equal(clickableSourceUrl(plugin({
    sourceUrl: "https://github.com/example/catalog.git"
  })), "https://github.com/example/catalog.git")
  assert.equal(clickableSourceUrl(plugin({
    sourceUrl: "git@github.com:example/plugin.git"
  })), "")
  assert.equal(clickableSourceUrl(null), "")
})

test("confirms updates only from a fresh successful snapshot", () => {
  const current = {
    ok: true,
    remoteChecked: true,
    stale: false,
    snapshotId: "snapshot-1",
    plugins: []
  }

  assert.equal(snapshotConfirmsUpdates(current, 0), true)
  assert.equal(snapshotConfirmsUpdates({ ...current, remoteChecked: false }, 0), false)
  assert.equal(snapshotConfirmsUpdates({ ...current, stale: true }, 0), false)
  assert.equal(snapshotConfirmsUpdates({ ...current, ok: false }, 0), false)
  assert.equal(snapshotConfirmsUpdates(current, 1), false)
})

test("reconciles successful plugin actions before the next network snapshot", () => {
  const snapshot = {
    ok: true,
    snapshotId: "snapshot-before-actions",
    self: {
      installedVersion: "0.0.53",
      availableVersion: "0.0.54",
      currentCommit: "self-old",
      availableCommit: "self-new",
      updateState: "update-available",
      versionUpdateAvailable: true,
      safeUpdate: true
    },
    plugins: [
      plugin({
        id: "b.install",
        version: "2.0.0",
        sourceUrl: "https://github.com/example/install.git",
        catalogCommit: "install-head",
        catalog: true
      }),
      plugin({
        id: "b.remove-catalog",
        installed: true,
        installedVersion: "1.0.0",
        installedPath: "/plugins/b.remove-catalog",
        installedSourceUrl: "https://github.com/example/remove.git",
        installType: "git",
        currentCommit: "remove-head",
        catalog: true
      }),
      plugin({
        id: "b.remove-local",
        installed: true,
        installType: "local",
        catalog: false
      }),
      plugin({
        id: "b.update",
        installed: true,
        installedVersion: "1.0.0",
        availableVersion: "2.0.0",
        currentCommit: "update-old",
        availableCommit: "update-new",
        updateState: "update-available",
        versionUpdateAvailable: true,
        safeUpdate: true,
        catalog: true
      }),
      plugin({
        id: "b.failed",
        installed: false,
        catalog: true
      })
    ]
  }
  const before = JSON.parse(JSON.stringify(snapshot))
  const reconciled = reconcileActionSnapshot(snapshot, [
    { id: "b.install", operation: "install", ok: true },
    { id: "b.remove-catalog", operation: "remove", ok: true },
    { id: "b.remove-local", operation: "remove", ok: true },
    { id: "b.update", operation: "update", ok: true },
    { id: "b.failed", operation: "install", ok: false },
    { id: "b.okomart", operation: "update", ok: true },
    { id: "Omarchy shell", operation: "reload", ok: true }
  ], "b.okomart")
  const plain = JSON.parse(JSON.stringify(reconciled))

  assert.deepEqual(snapshot, before)
  assert.equal(plain.plugins.length, 4)

  const installed = plain.plugins.find(item => item.id === "b.install")
  assert.equal(installed.installed, true)
  assert.equal(installed.installedVersion, "2.0.0")
  assert.equal(installed.installedSourceUrl,
    "https://github.com/example/install.git")
  assert.equal(installed.currentCommit, "install-head")
  assert.equal(installed.updateState, "up-to-date")

  const removed = plain.plugins.find(item => item.id === "b.remove-catalog")
  assert.equal(removed.installed, false)
  assert.equal("installedPath" in removed, false)
  assert.equal("updateState" in removed, false)
  assert.equal(plain.plugins.some(item => item.id === "b.remove-local"), false)

  const updated = plain.plugins.find(item => item.id === "b.update")
  assert.equal(updated.installedVersion, "2.0.0")
  assert.equal(updated.currentCommit, "update-new")
  assert.equal(updated.updateState, "up-to-date")
  assert.equal(updated.versionUpdateAvailable, false)
  assert.equal(updated.safeUpdate, false)

  assert.equal(plain.plugins.find(item => item.id === "b.failed").installed, false)
  assert.equal(plain.self.installedVersion, "0.0.54")
  assert.equal(plain.self.currentCommit, "self-new")
  assert.equal(plain.self.versionUpdateAvailable, false)
  assert.equal(plain.self.safeUpdate, false)
})

test("compacts high-DPI content only enough to retain the wide layout", () => {
  assert.equal(dpiCompactionScale(1200, 1200, 2), 1)
  assert.equal(dpiCompactionScale(1070, 1200, 2), 1070 / 1200)
  assert.equal(dpiCompactionScale(380, 600, 2), 380 / 600)
  assert.equal(dpiCompactionScale(250, 600, 2), 0.5)
  assert.equal(dpiCompactionScale(Number.NaN, 600, 2), 1)
})

test("orders selectable updates with Okomart first without mutation", () => {
  const alpha = { id: "b.alpha", safeUpdate: true }
  const beta = { id: "b.beta", safeUpdate: true }
  const self = { id: "b.okomart", safeUpdate: true }
  const blocked = { id: "b.blocked", safeUpdate: false }
  const updates = [alpha, blocked, beta, self, alpha]

  const result = Array.from(selectableUpdates(updates, "b.okomart"))
  assert.deepEqual(result, [self, alpha, beta])
  assert.deepEqual(updates, [alpha, blocked, beta, self, alpha])
})

test("parses Hyprland ARGB option colors", () => {
  assert.deepEqual(Array.from(hyprlandColorComponents(
    '{"option":"general:col.inactive_border","custom":"aa595959 0deg"}'
  )), [0x59, 0x59, 0x59, 0xaa])
  assert.deepEqual(Array.from(hyprlandColorComponents({
    custom: "0xcc112233 ff445566 45deg"
  })), [0x11, 0x22, 0x33, 0xcc])
  assert.deepEqual(Array.from(hyprlandColorComponents("not-json")), [])
})

test("renders catalog and installed versions from snapshot fields", () => {
  assert.equal(pluginVersionText(plugin({ version: "2.0" })), "2.0")
  assert.equal(pluginVersionText(plugin({ version: "" })), "Unknown")
  assert.equal(pluginVersionText(plugin({
    installed: true,
    version: "2.0",
    installedVersion: "1.0"
  })), "2.0 (installed 1.0)")
  assert.equal(pluginVersionText(null), "")
})

test("filters snapshot rows without re-sorting the backend order", () => {
  const plugins = [
    plugin({ id: "b.ten", name: "Tool 10", installed: true }),
    plugin({ id: "b.two", name: "Tool 2", installed: false }),
    plugin({ id: "b.author", name: "Other", author: "Toolsmith", installed: true })
  ]

  assert.deepEqual(Array.from(filterPlugins(plugins, "tool", true)), [
    plugins[0],
    plugins[2]
  ])
  assert.deepEqual(Array.from(filterPlugins(plugins, "", false)), plugins)
  assert.deepEqual(Array.from(filterPlugins(null, "", false)), [])
})

test("preserves selection by id and otherwise selects the first visible row", () => {
  const visible = [
    plugin({ id: "b.one" }),
    plugin({ id: "b.two" })
  ]
  assert.equal(resolveSelection(visible, "b.two"), "b.two")
  assert.equal(resolveSelection(visible, "b.gone"), "b.one")
  assert.equal(resolveSelection([], "b.gone"), "")
})

test("maps backend update states used by plugin details", () => {
  const available = plugin({
    installed: true,
    versionUpdateAvailable: true,
    updateState: "update-available"
  })
  assert.equal(updateState(available), "available")
  assert.equal(updateState(plugin({ updateState: "up-to-date" })), "current")
  assert.equal(updateState(plugin({ updateState: "dirty" })), "dirty")
  assert.equal(updateState(plugin({ updateState: "diverged" })), "diverged")
  assert.equal(updateState(plugin({ updateState: "ahead" })), "ahead")
  assert.equal(updateState(plugin({ updateState: "no-origin" })), "missing-origin")
  assert.equal(updateState(plugin({ updateState: "fetch-failed" })), "offline")
  assert.equal(updateState(plugin({ updateState: "unchecked" })), "checking")
  assert.equal(updateState(plugin({ updateState: "non-git" })), "unknown")
})

test("shows only actionable runtime update details", () => {
  const cases = [
    ["up-to-date", ""],
    ["diverged", "Update blocked: local and remote histories diverged"],
    ["ahead", "Installed checkout is ahead of its remote"],
    ["no-origin", "Update unavailable: Git checkout has no origin"],
    ["fetch-failed", "Update status unavailable"],
    ["unchecked", "Checking remote update status…"],
    ["non-git", "Local plugin; no Git update source"],
    ["development-link", "Development link; updates are managed externally"],
    ["invalid", "Update unavailable: installed manifest is invalid"]
  ]
  for (const [state, expected] of cases)
    assert.equal(updateDetailText(plugin({ installed: true, updateState: state })), expected)
  assert.equal(updateDetailText(plugin({ installed: false, updateState: "invalid" })), "")
})

test("blocks removal only for dirty Git checkouts", () => {
  const dirtyGit = plugin({
    installed: true,
    installType: "git",
    dirty: true,
    updateState: "dirty"
  })
  assert.equal(canRemovePlugin(dirtyGit), false)
  assert.match(removalBlockReason(dirtyGit), /local changes/)
  assert.equal(canRemovePlugin(plugin({
    installed: true,
    installType: "local",
    dirty: true,
    updateState: "non-git"
  })), true)
  assert.equal(canRemovePlugin(plugin({ installed: false })), false)
})

process.stdout.write(`${passed} Okomart model tests passed\n`)
