#!/bin/zsh
# Build both targets into the project dir.
set -e
cd "$(dirname "$0")"
swiftc Engine.swift speak-duck.swift -o speak-duck
swiftc Engine.swift SpeakDuckApp.swift -o SpeakDuck
echo "Built: ./speak-duck (CLI)  ./SpeakDuck (menu-bar app)"
