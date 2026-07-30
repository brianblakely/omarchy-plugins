#!/usr/bin/env node

import {
  chmodSync,
  closeSync,
  fsyncSync,
  lstatSync,
  mkdtempSync,
  openSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync
} from "node:fs"
import { execFileSync } from "node:child_process"
import { tmpdir } from "node:os"
import { basename, dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const BEGIN_MARKER = "<!-- BEGIN GENERATED PLUGIN CATALOG -->"
const END_MARKER = "<!-- END GENERATED PLUGIN CATALOG -->"
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url))
const REPOSITORY_ROOT = resolve(SCRIPT_DIR, "..")

function fail(message) {
  throw new Error(message)
}

function compareCodeUnits(first, second) {
  if (first < second) return -1
  if (first > second) return 1
  return 0
}

function requireRegularFile(path, label) {
  let stat
  try {
    stat = lstatSync(path)
  } catch {
    fail(`${label} does not exist: ${path}`)
  }
  if (stat.isSymbolicLink() || !stat.isFile())
    fail(`${label} must be a regular file: ${path}`)
  return stat
}

function canonicalPluginUrl(value, lineNumber) {
  if (value.length === 0)
    fail(`plugins.txt line ${lineNumber} is blank`)
  if (value.trim() !== value || /[\u0000-\u001f\u007f]/u.test(value))
    fail(`plugins.txt line ${lineNumber} contains whitespace or control characters`)
  if (!value.endsWith(".git"))
    fail(`plugins.txt line ${lineNumber} must end in .git`)
  if (value.includes("%"))
    fail(`plugins.txt line ${lineNumber} must use a canonical public DNS URL`)

  let parsed
  try {
    parsed = new URL(value)
  } catch {
    fail(`plugins.txt line ${lineNumber} is not a valid URL`)
  }
  if (parsed.protocol !== "https:")
    fail(`plugins.txt line ${lineNumber} must use https`)
  if (!parsed.hostname || parsed.username || parsed.password
      || parsed.search || parsed.hash)
    fail(`plugins.txt line ${lineNumber} is not a public canonical HTTPS URL`)
  if (parsed.href !== value)
    fail(`plugins.txt line ${lineNumber} is not in canonical URL form`)
  const labels = parsed.hostname.split(".")
  if (labels.length < 2
      || parsed.hostname.length > 253
      || /^[0-9.]+$/u.test(parsed.hostname)
      || labels.some(label =>
        label.length === 0
        || label.length > 63
        || !/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/u.test(label))
      || parsed.port === "0")
    fail(`plugins.txt line ${lineNumber} must use a canonical public DNS URL`)
  if (!/^\/[-A-Za-z0-9._~/]+\.git$/u.test(parsed.pathname))
    fail(`plugins.txt line ${lineNumber} must use a canonical repository path`)
  return value
}

function readRegistry(path) {
  requireRegularFile(path, "Plugin registry")
  let source = readFileSync(path, "utf8").replace(/\r\n/gu, "\n")
  if (source.includes("\r"))
    fail("plugins.txt contains an unsupported carriage return")
  if (source.endsWith("\n")) source = source.slice(0, -1)
  if (source.length === 0) fail("plugins.txt must contain at least one URL")

  const seen = new Set()
  const urls = source.split("\n").map((line, index) => {
    const url = canonicalPluginUrl(line, index + 1)
    if (seen.has(url))
      fail(`plugins.txt contains a duplicate URL: ${url}`)
    seen.add(url)
    return url
  })
  return urls.sort(compareCodeUnits)
}

function cloneTimeoutMilliseconds() {
  const value = process.env.OKOMART_CATALOG_CLONE_TIMEOUT_SECONDS || "60"
  if (!/^[1-9][0-9]*$/u.test(value))
    fail("OKOMART_CATALOG_CLONE_TIMEOUT_SECONDS must be an integer from 1 to 600")
  const seconds = Number(value)
  if (!Number.isSafeInteger(seconds) || seconds > 600)
    fail("OKOMART_CATALOG_CLONE_TIMEOUT_SECONDS must be an integer from 1 to 600")
  return seconds * 1000
}

function normalizedMetadata(value, field, url) {
  if (typeof value !== "string" || value.trim().length === 0)
    fail(`${url} manifest field '${field}' must be a nonblank string`)
  return value.replace(/\r\n?/gu, "\n").trim().replace(/\s+/gu, " ")
}

function escapeMarkdown(value) {
  const escapedPunctuation = new Set(["\\", "|", "`", "*", "_", "[", "]", "~", "!"])
  let escaped = ""
  for (const character of value) {
    if (character === "&") escaped += "&amp;"
    else if (character === "<") escaped += "&lt;"
    else if (character === ">") escaped += "&gt;"
    else if (escapedPunctuation.has(character)) escaped += `\\${character}`
    else escaped += character
  }
  return escaped
}

function readPluginRow(repository, url) {
  const manifestPath = join(repository, "manifest.json")
  requireRegularFile(manifestPath, `${url} root manifest`)

  let manifest
  try {
    manifest = JSON.parse(readFileSync(manifestPath, "utf8"))
  } catch {
    fail(`${url} root manifest is not valid JSON`)
  }
  if (manifest === null || typeof manifest !== "object" || Array.isArray(manifest))
    fail(`${url} root manifest must be a JSON object`)

  return {
    url,
    name: normalizedMetadata(manifest.name, "name", url),
    author: normalizedMetadata(manifest.author, "author", url),
    description: normalizedMetadata(manifest.description, "description", url)
  }
}

function clonePlugin(url, destination, timeout) {
  try {
    execFileSync("git", [
      "clone",
      "--quiet",
      "--depth", "1",
      "--no-recurse-submodules",
      "--",
      url,
      destination
    ], {
      env: {
        ...process.env,
        GIT_TERMINAL_PROMPT: "0",
        LC_ALL: "C"
      },
      timeout,
      killSignal: "SIGTERM",
      stdio: ["ignore", "ignore", "pipe"]
    })
  } catch (error) {
    if (error && error.code === "ETIMEDOUT")
      fail(`Timed out cloning plugin repository: ${url}`)
    fail(`Could not clone plugin repository: ${url}`)
  }
}

function generatedCatalog(rows) {
  const lines = [
    BEGIN_MARKER,
    "<!-- Generated by scripts/generate-plugin-catalog.mjs from plugins.txt. -->",
    "",
    "| Plugin | Author | Description |",
    "| --- | --- | --- |"
  ]
  for (const row of rows) {
    lines.push(
      `| [${escapeMarkdown(row.name)}](<${row.url}>)`
      + ` | ${escapeMarkdown(row.author)}`
      + ` | ${escapeMarkdown(row.description)} |`
    )
  }
  lines.push(END_MARKER)
  return lines
}

function countOccurrences(source, token) {
  let count = 0
  let offset = 0
  while ((offset = source.indexOf(token, offset)) !== -1) {
    count += 1
    offset += token.length
  }
  return count
}

function regexEscape(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&")
}

function exactMarkerMatch(source, marker) {
  const expression = new RegExp(`^${regexEscape(marker)}\\r?$`, "gmu")
  return [...source.matchAll(expression)]
}

function replaceGeneratedCatalog(readme, lines) {
  if (countOccurrences(readme, BEGIN_MARKER) !== 1
      || countOccurrences(readme, END_MARKER) !== 1)
    fail("README must contain exactly one generated catalog marker pair")

  const beginMatches = exactMarkerMatch(readme, BEGIN_MARKER)
  const endMatches = exactMarkerMatch(readme, END_MARKER)
  if (beginMatches.length !== 1 || endMatches.length !== 1)
    fail("README catalog markers must each occupy their own line")

  const begin = beginMatches[0]
  const end = endMatches[0]
  if (begin.index >= end.index)
    fail("README generated catalog markers are out of order")

  const beginEnding = begin[0].endsWith("\r") ? "\r\n" : "\n"
  const endEnding = end[0].endsWith("\r") ? "\r\n" : "\n"
  if (beginEnding !== endEnding)
    fail("README generated catalog markers use inconsistent line endings")

  let replaceEnd = end.index + end[0].length
  let endedWithNewline = false
  if (readme[replaceEnd] === "\n") {
    replaceEnd += 1
    endedWithNewline = true
  }
  const generated = lines.join(beginEnding)
    + (endedWithNewline ? beginEnding : "")
  return readme.slice(0, begin.index) + generated + readme.slice(replaceEnd)
}

function writeAtomicallyIfChanged(path, content) {
  const current = readFileSync(path, "utf8")
  if (content === current) return false

  const stat = requireRegularFile(path, "README")
  const stageDirectory = mkdtempSync(join(dirname(path), `.${basename(path)}.catalog-`))
  const stagePath = join(stageDirectory, basename(path))
  let descriptor
  try {
    descriptor = openSync(stagePath, "wx", stat.mode)
    writeFileSync(descriptor, content, "utf8")
    fsyncSync(descriptor)
    closeSync(descriptor)
    descriptor = undefined
    chmodSync(stagePath, stat.mode)
    renameSync(stagePath, path)
  } finally {
    if (descriptor !== undefined) closeSync(descriptor)
    rmSync(stageDirectory, { recursive: true, force: true })
  }
  return true
}

function main() {
  if (process.argv.length > 4)
    fail("Usage: generate-plugin-catalog.mjs [plugins.txt] [README.md]")

  const registryPath = resolve(process.argv[2] || join(REPOSITORY_ROOT, "plugins.txt"))
  const readmePath = resolve(process.argv[3] || join(REPOSITORY_ROOT, "README.md"))
  requireRegularFile(readmePath, "README")
  const currentReadme = readFileSync(readmePath, "utf8")
  // Fail before any network access when the destination is not safely
  // marker-owned. The real rows replace this validation-only block below.
  replaceGeneratedCatalog(currentReadme, [BEGIN_MARKER, END_MARKER])

  const urls = readRegistry(registryPath)
  const cloneTimeout = cloneTimeoutMilliseconds()
  const cloneRoot = mkdtempSync(join(tmpdir(), "okomart-plugin-catalog-"))
  let rows
  try {
    rows = urls.map((url, index) => {
      const destination = join(cloneRoot, `plugin-${String(index + 1).padStart(4, "0")}`)
      clonePlugin(url, destination, cloneTimeout)
      return readPluginRow(destination, url)
    })
  } finally {
    rmSync(cloneRoot, { recursive: true, force: true })
  }

  const nextReadme = replaceGeneratedCatalog(currentReadme, generatedCatalog(rows))
  const changed = writeAtomicallyIfChanged(readmePath, nextReadme)
  process.stdout.write(
    `${changed ? "Updated" : "Verified"} ${basename(readmePath)}`
    + ` with ${rows.length} plugin${rows.length === 1 ? "" : "s"}.\n`
  )
}

try {
  main()
} catch (error) {
  process.stderr.write(`generate-plugin-catalog: ${error.message}\n`)
  process.exitCode = 1
}
