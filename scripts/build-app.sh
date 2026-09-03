#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="$project_dir/build/DiskCleaner.app"
contents_dir="$app_dir/Contents"

"$project_dir/scripts/build-core.sh"
"$project_dir/scripts/generate-icon.sh"

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$contents_dir/Frameworks"
swiftc \
  -O \
  -target arm64-apple-macosx14.0 \
  -I "$project_dir/build/modules" \
  -L "$project_dir/build/modules" \
  -lCleanerCore \
  -framework AppKit \
  -framework SwiftUI \
  "$project_dir"/Sources/DiskCleaner/*.swift \
  -o "$contents_dir/MacOS/DiskCleaner" \
  -Xlinker -rpath \
  -Xlinker @executable_path/../Frameworks
cp "$project_dir/build/modules/libCleanerCore.dylib" "$contents_dir/Frameworks/"
cp "$project_dir/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Assets/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
