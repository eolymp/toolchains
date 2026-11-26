#!/usr/bin/env bash
# Builds the toolchain for Linux or Windows from conda-forge. Usage: build.sh <linux-x64|linux-arm64|win32-x64>; output in out/.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$(dirname "$here")/out"
name="$1"
case "$name" in
  linux-x64) os=linux driver=gcc/bin/x86_64-conda-linux-gnu-g++ cxx=gcc/bin/g++ python=python/bin/python3 flags='["-static-libstdc++", "-static-libgcc"]' ;;
  linux-arm64) os=linux driver=gcc/bin/aarch64-conda-linux-gnu-g++ cxx=gcc/bin/g++ python=python/bin/python3 flags='["-static-libstdc++", "-static-libgcc"]' ;;
  win32-x64) os=win32 driver=gcc/Library/bin/x86_64-w64-mingw32-g++.exe cxx=gcc/Library/bin/g++.exe python=python/python.exe flags='["-static"]' ;;
  *) echo "unknown system: $name"; exit 1 ;;
esac

native() {
  if [ "$os" = win32 ]; then cygpath -w "$1"; else echo "$1"; fi
}

work="$(mktemp -d)"
root="$work/toolchain"
sources="$out/source"
mkdir -p "$root/licenses" "$out" "$sources/files" "$sources/recipes"
export MAMBA_ROOT_PREFIX="$(native "$work/mamba")"

micromamba create -y -q -p "$(native "$root/gcc")" -f "$(native "$here/conda-lock.yml")"
if [ "$os" = win32 ]; then cp "$root/$driver" "$root/$cxx"; else ln -s "$(basename "$driver")" "$root/$cxx"; fi

fetch() {
  curl -fsSL --retry 3 -o "$2" "$1"
  [ -z "$3" ] || echo "$3  $2" | sha256sum -c --quiet -
}

while read -r platform sha256 url; do
  if [ "$platform" = "$os-source" ]; then
    file="$sources/files/$(basename "$url")"
    [ -e "$file" ] || fetch "$url" "$file" "$sha256"
    continue
  fi
  [ "$platform" = "$name" ] || continue
  file="$work/$(basename "$url")"
  fetch "$url" "$file" "$sha256"
  case "$file" in
    *.tar.gz) tar -xzf "$file" -C "$root" ;;
    *.zip)
      if [ "$os" = win32 ]; then 7z x -bso0 -y -o"$(native "$work/zip")" "$(native "$file")"; else unzip -q "$file" -d "$work/zip"; fi
      mv "$work"/zip/clangd_* "$root/clangd"
      ;;
  esac
done < "$here/pins.txt"

for record in "$root"/gcc/conda-meta/*.json; do
  package="$(jq -r .extracted_package_dir "$record")"
  [ "$os" != win32 ] || package="$(cygpath -u "$package")"
  info="$package/info"
  dist="$(basename "$package")"
  license="$(jq -r .license "$info/about.json")"
  printf '%s\t%s\n' "$dist" "$license" >> "$root/licenses/packages.txt"
  case "$license" in *GPL*) ;; *) continue ;; esac
  cp -R "$info/recipe" "$sources/recipes/$dist"
  yq -o tsv '[.source] | flatten | .[] | select(.url or .git_url) | [(.url | [.] | flatten | .[0]) // (.git_url + "/archive/" + .git_rev + ".tar.gz"), (.sha256 // "")]' "$info/recipe/meta.yaml" |
    while IFS=$'\t' read -r url sha256; do
      case "$url" in *.src.rpm) ;; *.rpm) continue ;; esac
      file="$sources/files/$(basename "$url")"
      case "$url" in https://github.com/*/archive/*) file="$sources/files/$(basename "$(dirname "$(dirname "$url")")")-$(basename "$url")" ;; esac
      [ -e "$file" ] || fetch "$url" "$file" "$sha256"
    done
done
tar -xf "$(ls "$sources"/files/gcc-14.*.tar.*)" -C "$work" --wildcards '*/COPYING*'
cp "$work"/gcc-*/COPYING* "$root/licenses/"

archive="$out/$name.tar.gz"
tar -czf "$archive" -C "$root" .

test="$work/test"
mkdir -p "$test/unpacked"
if [ "$os" = win32 ]; then
  /c/Windows/System32/tar.exe -xzf "$(native "$archive")" -C "$(native "$test/unpacked")"
else
  tar -xzf "$archive" -C "$test/unpacked"
fi
rm -rf "$root"
printf '#include <bits/stdc++.h>\nint main() { std::vector<int> v{3, 1, 2}; std::ranges::sort(v); std::cout << v[0] << v[2] << "\\n"; }\n' > "$test/a.cpp"
PATH="$(dirname "$test/unpacked/$cxx"):$PATH" "$test/unpacked/$cxx" -std=c++23 -O2 $(jq -r '.[]' <<< "$flags") "$(native "$test/a.cpp")" -o "$(native "$test/a")"
[ "$("$test/a" | tr -d '\r')" = 13 ]
"$test/unpacked/$python" -c 'import sys; assert sys.version_info[:2] == (3, 14)'

clangd=""
for candidate in clangd/bin/clangd clangd/bin/clangd.exe gcc/bin/clangd; do
  [ ! -e "$test/unpacked/$candidate" ] || clangd="$candidate"
done
if [ -n "$clangd" ]; then
  "$test/unpacked/$clangd" --version
  printf -- '-std=c++23\n' > "$test/compile_flags.txt"
  checked="$(PATH="$(dirname "$test/unpacked/$cxx"):$PATH" "$test/unpacked/$clangd" --check="$(native "$test/a.cpp")" --query-driver="$(native "$(dirname "$test/unpacked/$cxx")")/*" 2>&1)" || true
  grep -q "All checks completed, 0 errors" <<< "$checked" || { echo "$checked"; exit 1; }
fi

jq -n --arg sha256 "$(sha256sum "$archive" | cut -d' ' -f1)" --arg cxx "$cxx" --arg python "$python" --arg clangd "$clangd" --argjson flags "$flags" \
  '{sha256: $sha256, cxx: $cxx, python: $python, clangd: $clangd, flags: $flags}' > "$out/$name.json"
cat "$out/$name.json"
