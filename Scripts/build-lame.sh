#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
version="4.0"
expected_sha256="3df5124d5ad3a98312ffd7ba6a9b36230e4f8a3e66d3ce0f425e336c32d216eb"
cache_dir="$project_dir/.build/lame-$version"
archive="$cache_dir/lame-$version.tar.gz"
source_dir="$cache_dir/source"
install_dir="$cache_dir/install"
executable="$install_dir/bin/lame"

if [[ -x "$executable" ]]; then
    echo "$executable"
    exit 0
fi

mkdir -p "$cache_dir"
if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 3 \
        "https://downloads.sourceforge.net/project/lame/lame/$version/lame-$version.tar.gz" \
        --output "$archive"
fi

actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "LAME archive checksum mismatch" >&2
    exit 1
fi

rm -rf "$source_dir" "$install_dir"
mkdir -p "$source_dir" "$install_dir"
tar -xzf "$archive" -C "$source_dir" --strip-components=1

(
    cd "$source_dir"
    PKG_CONFIG="$project_dir/Scripts/pkg-config-stub.sh" \
    CFLAGS="-O2 -arch arm64 -mmacosx-version-min=15.0 -include locale.h" \
    LDFLAGS="-arch arm64 -mmacosx-version-min=15.0" \
        ./configure \
            --prefix="$install_dir" \
            --disable-shared \
            --enable-static \
            --disable-decoder
    make -j"$(sysctl -n hw.logicalcpu)"
    make install
)

test -x "$executable"
echo "$executable"
