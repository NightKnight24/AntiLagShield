#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$DIR/build_all.sh" "$@"

cd "$DIR/dist"
shasum -a 256 *.deb > SHA256SUMS.txt
python3 "$DIR/make_repo.py"
