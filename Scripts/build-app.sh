#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${CONFIGURATION:-release}"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    signing_identity="$CODE_SIGN_IDENTITY"
elif security find-identity -v -p codesigning | grep -q '"AudioToText Local Release"'; then
    signing_identity="AudioToText Local Release"
else
    signing_identity="-"
fi
output_dir="$project_dir/dist"
app_dir="$output_dir/AudioToText.app"
contents_dir="$app_dir/Contents"
lame_executable="$project_dir/.build/lame-4.0/install/bin/lame"
lame_source_dir="$project_dir/.build/lame-4.0/source"

cd "$project_dir"
"$project_dir/Scripts/build-lame.sh"
swift build -c "$configuration" --product AudioToText
bin_dir="$(swift build -c "$configuration" --show-bin-path)"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources/bin" "$contents_dir/Resources/Licenses"
cp "$bin_dir/AudioToText" "$contents_dir/MacOS/AudioToText"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
cp "$lame_executable" "$contents_dir/Resources/bin/lame"
cp "$lame_source_dir/COPYING" "$contents_dir/Resources/Licenses/LAME-LGPL.txt"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$contents_dir/Resources/THIRD_PARTY_NOTICES.md"
chmod 755 "$contents_dir/Resources/bin/lame"

for localization in "$project_dir"/Resources/*.lproj(N); do
    cp -R "$localization" "$contents_dir/Resources/"
done

for bundle in "$bin_dir"/*.bundle(N); do
    cp -R "$bundle" "$contents_dir/Resources/"
done

codesign --force --options runtime --sign "$signing_identity" "$contents_dir/Resources/bin/lame"
codesign --force --deep --options runtime --sign "$signing_identity" "$app_dir"
echo "$app_dir"
