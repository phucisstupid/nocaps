#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swift-format lint --strict --recursive Sources Tests scripts/render-icons.swift
for script in scripts/*.sh; do
    bash -n "$script"
done
plutil -lint Info.plist
