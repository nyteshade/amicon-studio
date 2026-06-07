#!/usr/bin/env bash
#
# AmigaIconWriter — build / test / run helper for macOS.
#
#   ./build.sh           build everything (kit + CLI + app) via SwiftPM
#   ./build.sh test      run the AmigaIconKit unit tests
#   ./build.sh run       build & launch the SwiftUI app
#   ./build.sh app       build the app the way Xcode/CI does (xcodebuild)
#   ./build.sh cli ...   run the amigaicon CLI (e.g. ./build.sh cli --help)
#   ./build.sh xcode     open the package in Xcode (pick the AmigaIconWriterApp
#                        scheme and run on "My Mac")
#
# Requires a Swift toolchain (Xcode 15+; Xcode 26 enables Liquid Glass styling).
set -euo pipefail
cd "$(dirname "$0")"

cmd="${1:-build}"
case "$cmd" in
  build)
    swift build
    echo "✅ Built. Try:  ./build.sh run   ·   open in Xcode:  ./build.sh xcode"
    ;;
  test)
    swift test
    ;;
  run)
    swift run AmigaIconWriterApp
    ;;
  app)
    xcodebuild -scheme AmigaIconWriterApp -destination 'platform=macOS' build
    ;;
  cli)
    shift
    swift run amigaicon "$@"
    ;;
  xcode)
    open Package.swift
    ;;
  *)
    echo "usage: ./build.sh [build|test|run|app|cli ...|xcode]" >&2
    exit 2
    ;;
esac
