#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
"$project_dir/scripts/build-core.sh"

swiftc \
  -parse-as-library \
  -target arm64-apple-macosx14.0 \
  -I "$project_dir/build/modules" \
  -L "$project_dir/build/modules" \
  -lCleanerCore \
  "$project_dir/Tests/CleanerCoreTests/CleanerServiceTests.swift" \
  -o "$project_dir/build/CleanerCoreTests" \
  -Xlinker -rpath \
  -Xlinker "$project_dir/build/modules"

"$project_dir/build/CleanerCoreTests"
