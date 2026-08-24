#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

node "$ROOT_DIR/tests/model.test.js"
"$ROOT_DIR/tests/launcher.test.sh"
"$ROOT_DIR/tests/qml.test.sh"

if [[ -x $ROOT_DIR/tests/backend.test.sh ]]; then
  "$ROOT_DIR/tests/backend.test.sh"
fi
