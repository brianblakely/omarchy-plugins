#!/usr/bin/env node

import { readFileSync, writeFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, resolve } from "node:path"

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const sourcePath = resolve(process.argv[2] || resolve(root, "assets/moped-source.svg"))
const outputPath = resolve(process.argv[3] || resolve(root, "assets/MopedPaths.js"))
const svg = readFileSync(sourcePath, "utf8")

const viewBox = svg.match(/\bviewBox="([^"]+)"/)
const pathMatches = [...svg.matchAll(/<path\b[^>]*\bd="([^"]+)"[^>]*>/g)]
if (!viewBox) throw new Error("The scooter SVG has no viewBox")
if (pathMatches.length !== 2)
  throw new Error(`Expected two scooter paths, found ${pathMatches.length}`)

const bounds = viewBox[1].trim().split(/\s+/).map(Number)
if (bounds.length !== 4 || bounds.some(value => !Number.isFinite(value)))
  throw new Error("The scooter SVG viewBox is invalid")

const coordinatePairs = pathMatches.flatMap(match =>
  [...match[1].matchAll(/[ML]\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)/g)]
    .map(pair => [Number(pair[1]), Number(pair[2])]))
if (coordinatePairs.length === 0)
  throw new Error("The scooter SVG has no supported path coordinates")
const xValues = coordinatePairs.map(pair => pair[0])
const yValues = coordinatePairs.map(pair => pair[1])
const artX = Math.min(...xValues)
const artY = Math.min(...yValues)
const artRight = Math.max(...xValues)
const artBottom = Math.max(...yValues)

const output = `.pragma library

// Generated from assets/moped-source.svg. Do not trace or edit these paths by hand.
var viewBoxX = ${bounds[0]}
var viewBoxY = ${bounds[1]}
var viewBoxWidth = ${bounds[2]}
var viewBoxHeight = ${bounds[3]}
var artX = ${artX}
var artY = ${artY}
var artWidth = ${artRight - artX}
var artHeight = ${artBottom - artY}
var bodyworkPath = ${JSON.stringify(pathMatches[0][1])}
var lineworkPath = ${JSON.stringify(pathMatches[1][1])}
`

writeFileSync(outputPath, output)
