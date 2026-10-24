#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_path="$project_dir/dist/AudioToText.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")"
dmg_path="$project_dir/dist/AudioToText-$version.dmg"
checksum_path="$dmg_path.sha256"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/AudioToText-dmg.XXXXXX")"

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT

"$project_dir/Scripts/build-app.sh"

cp -R "$app_path" "$staging_dir/AudioToText.app"
ln -s /Applications "$staging_dir/Applications"
cp "$project_dir/LICENSE" "$staging_dir/LICENSE.txt"

rm -f "$dmg_path" "$checksum_path"
hdiutil create \
    -volname "AudioToText" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path"

(
    cd "$project_dir/dist"
    shasum -a 256 "${dmg_path:t}" > "${checksum_path:t}"
)

echo "$dmg_path"
echo "$checksum_path"
