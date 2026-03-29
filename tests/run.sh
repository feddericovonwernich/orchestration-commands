#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

printf '==> installer regression tests\n'
bash "$ROOT_DIR/tests/install.test.sh"

printf '\n'
printf '==> /orchestrate contract tests\n'
bash "$ROOT_DIR/tests/orchestrate-contract.test.sh"

printf '\n==> /orchestrate live smoke tests\n'
bash "$ROOT_DIR/tests/orchestrate-live.test.sh"

printf '\nAll selected /orchestrate tests passed.\n'
