#!/bin/zsh
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
xcodebuild -project "$PROJECT_DIR/WriteBench.xcodeproj" -scheme WriteBench -configuration Release -derivedDataPath "$PROJECT_DIR/build" build
ditto "$PROJECT_DIR/build/Build/Products/Release/WriteBench.app" "$PROJECT_DIR/WriteBench.app"
