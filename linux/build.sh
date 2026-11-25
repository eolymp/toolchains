#!/usr/bin/env bash
# Builds the Linux toolchain. Usage: build.sh <x64|arm64>; output in out/.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$(dirname "$here")/out"
arch="$1"
case "$arch" in
  x64) triple=x86_64-conda-linux-gnu ;;
  arm64) triple=aarch64-conda-linux-gnu ;;
  *) echo "unknown architecture: $arch"; exit 1 ;;
esac

work="$(mktemp -d)"
root="$work/toolchain"
sources="$out/source"
export MAMBA_ROOT_PREFIX="$work/mamba"
mkdir -p "$root" "$out" "$sources/files" "$sources/recipes"

micromamba create -y -q -p "$root/gcc" -f "$here/conda-lock.yml"

fetch() {
  curl -fsSL --retry 3 -o "$2" "$1"
  [ -z "$3" ] || echo "$3  $2" | sha256sum -c --quiet -
}

while read -r platform sha256 url; do
  if [ "$platform" = source ]; then
    file="$sources/files/$(basename "$url")"
    [ -e "$file" ] || fetch "$url" "$file" "$sha256"
    continue
  fi
  [ "$platform" = "$arch" ] || continue
  file="$work/$(basename "$url")"
  fetch "$url" "$file" "$sha256"
  case "$file" in
    *.tar.gz) tar -xzf "$file" -C "$root" ;;
    *.zip) unzip -q "$file" -d "$work/zip" && mv "$work"/zip/clangd_* "$root/clangd" ;;
  esac
done < "$here/pins.txt"

mkdir -p "$root/licenses"
for record in "$root"/gcc/conda-meta/*.json; do
  package="$(jq -r .extracted_package_dir "$record")"
  info="$package/info"
  dist="$(basename "$package")"
  license="$(jq -r .license "$info/about.json")"
  printf '%s\t%s\n' "$dist" "$license" >> "$root/licenses/packages.txt"
  case "$license" in *GPL*) ;; *) continue ;; esac
  cp -R "$info/recipe" "$sources/recipes/$dist"
  yq -o tsv '[.source] | flatten | .[] | select(.url) | [(.url | [.] | flatten | .[0]), (.sha256 // "")]' "$info/recipe/meta.yaml" |
    while IFS=$'\t' read -r url sha256; do
      case "$url" in *.src.rpm) ;; *.rpm) continue ;; esac
      file="$sources/files/$(basename "$url")"
      [ -e "$file" ] || fetch "$url" "$file" "$sha256"
    done
done
tar -xf "$(ls "$sources"/files/gcc-14.*.tar.*)" -C "$work" --wildcards '*/COPYING*'
cp "$work"/gcc-*/COPYING* "$root/licenses/"

archive="$out/linux-$arch.tar.gz"
tar -czf "$archive" -C "$root" .

test="$work/test"
mkdir -p "$test/unpacked"
tar -xzf "$archive" -C "$test/unpacked"
rm -rf "$root"
printf '#include <bits/stdc++.h>\nint main() { std::vector<int> v{3, 1, 2}; std::ranges::sort(v); std::cout << v[0] << v[2] << "\\n"; }\n' > "$test/a.cpp"
"$test/unpacked/gcc/bin/$triple-g++" -std=c++23 -O2 -static-libstdc++ -static-libgcc "$test/a.cpp" -o "$test/a"
[ "$("$test/a")" = 13 ]
"$test/unpacked/python/bin/python3" -c 'import sys; assert sys.version_info[:2] == (3, 14)'
[ ! -e "$test/unpacked/clangd" ] || "$test/unpacked/clangd/bin/clangd" --version

clangd=""
[ ! -e "$test/unpacked/clangd" ] || clangd=clangd/bin/clangd
jq -n --arg sha256 "$(sha256sum "$archive" | cut -d' ' -f1)" --arg cxx "gcc/bin/$triple-g++" --arg clangd "$clangd" \
  '{sha256: $sha256, cxx: $cxx, python: "python/bin/python3", clangd: $clangd, flags: ["-static-libstdc++", "-static-libgcc"]}' > "$out/linux-$arch.json"
cat "$out/linux-$arch.json"
