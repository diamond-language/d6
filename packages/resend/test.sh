#!/usr/bin/env bash
set -euo pipefail

diamond="${DIAMOND_BIN:-diamond}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
test_project="$(mktemp -d)"
trap 'rm -rf "$test_project"' EXIT
"$root/tools/install_local_cuts.sh" "$test_project" >/dev/null
cp "$root/packages/resend/test/resend_test.d6" "$test_project/"
cd "$test_project"

"$diamond" resend_test.d6

echo "1 resend test program passed"
