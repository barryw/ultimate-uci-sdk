#!/bin/sh
set -eu

version=${1:?usage: tools/package-release.sh vX.Y.Z}
case "$version" in
    v[0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "invalid release version: $version" >&2; exit 2 ;;
esac

dist=dist
name="ultimate-uci-sdk-$version"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

rm -rf "$dist"
mkdir -p "$dist" "$tmp/$name"
git archive --format=tar HEAD | tar -xf - -C "$tmp/$name"
printf '%s\n' "$version" > "$tmp/$name/VERSION"

# Add ignored build products to the source tree at their normal paths.
cp bindings/cc65/build/ultimate.lib "$tmp/$name/bindings/cc65/"
cp bindings/blob/build/ultimate-8000.bin \
   bindings/blob/build/ultimate-8000.reloc "$tmp/$name/bindings/blob/"
cp src/basic/uci.prg src/basic/uci.crt "$tmp/$name/src/basic/"
cp examples/asm/identify.prg "$tmp/$name/examples/asm/"
cp examples/cc65/identify.prg "$tmp/$name/examples/cc65/"
cp demos/sid-visualizer/sid-visualizer.prg \
   "$tmp/$name/demos/sid-visualizer/"
cp guide/guide.pdf "$tmp/$name/guide/"

tar -czf "$dist/$name.tar.gz" -C "$tmp" "$name"
cp guide/guide.pdf "$dist/ultimate-sdk-guide-$version.pdf"
cp bindings/cc65/build/ultimate.lib "$dist/ultimate-$version.lib"
cp bindings/blob/build/ultimate-8000.bin "$dist/ultimate-8000-$version.bin"
cp bindings/blob/build/ultimate-8000.reloc "$dist/ultimate-8000-$version.reloc"
cp src/basic/uci.prg "$dist/uci-$version.prg"
cp src/basic/uci.crt "$dist/uci-$version.crt"
cp demos/sid-visualizer/sid-visualizer.prg \
   "$dist/ultimate-sid-visualizer-$version.prg"

if command -v sha256sum >/dev/null 2>&1; then
    (cd "$dist" && sha256sum -- * > SHA256SUMS)
else
    (cd "$dist" && shasum -a 256 -- * > SHA256SUMS)
fi
