#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${CONFIGURATION:-release}"
signing_identity="${CODE_SIGN_IDENTITY:--}"
output_dir="$project_dir/dist"
app_dir="$output_dir/AudioToText.app"
contents_dir="$app_dir/Contents"

cd "$project_dir"
swift build -c "$configuration" --product AudioToText
bin_dir="$(swift build -c "$configuration" --show-bin-path)"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$bin_dir/AudioToText" "$contents_dir/MacOS/AudioToText"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"

for bundle in "$bin_dir"/*.bundle(N); do
    cp -R "$bundle" "$contents_dir/Resources/"
done

codesign --force --deep --sign "$signing_identity" "$app_dir"
echo "$app_dir"
