#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
output_dir="$project_dir/build/modules"
mkdir -p "$output_dir"

swiftc \
  -parse-as-library \
  -emit-library \
  -emit-module \
  -module-name CleanerCore \
  -module-link-name CleanerCore \
  -target arm64-apple-macosx14.0 \
  "$project_dir"/Sources/CleanerCore/*.swift \
  -emit-module-path "$output_dir/CleanerCore.swiftmodule" \
  -o "$output_dir/libCleanerCore.dylib" \
  -Xlinker -install_name \
  -Xlinker @rpath/libCleanerCore.dylib
