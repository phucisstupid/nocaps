#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swift-format lint --strict --recursive Sources Tests
for script in scripts/*.sh; do
    bash -n "$script"
done
plutil -lint Info.plist
if [ -f Casks/nocaps.rb ]; then
    ruby -c Casks/nocaps.rb
fi
