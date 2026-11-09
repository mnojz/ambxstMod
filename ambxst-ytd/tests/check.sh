#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
bash -n scripts/install.sh
python3 -m json.tool ambxst.mod.json >/dev/null
python3 -B -m unittest discover -s tests -p 'test_*.py' -v
node --test tests/test_services.js
git diff --check -- . ':(exclude)patches/*.patch'
