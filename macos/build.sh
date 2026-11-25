#!/usr/bin/env bash
# Builds the macOS toolchain for the macOS it runs on. Usage: build.sh; output in out/.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$(dirname "$here")/out"
formula=gcc@14
version=14.4.0
case "$(uname -m)" in arm64) arch=arm64 ;; x86_64) arch=x64 ;; *) echo "unknown machine: $(uname -m)"; exit 1 ;; esac
name="darwin-$arch-$(uname -r | cut -d. -f1)"

work="$(mktemp -d)"
root="$work/toolchain"
sources="$out/source"
mkdir -p "$root/brew" "$root/licenses" "$sources/files" "$sources/recipes"

brew install "$formula"
installed="$(brew info --json=v2 "$formula" | jq -r '.formulae[0].installed[0].version')"
[ "$installed" = "$version" ] || { echo "Homebrew installed $formula $installed, expected $version"; exit 1; }

fetch() {
  curl -fsSL --retry 3 -o "$2" "$1"
  [ -z "$3" ] || echo "$3  $2" | shasum -a 256 -c --quiet -
}

for each in $formula $(brew deps "$formula"); do
  cp -R "$(realpath "$(brew --prefix "$each")")" "$root/brew/$each"
  info="$(brew info --json=v2 "$each" | jq '.formulae[0]')"
  jq -r '[.name, .installed[0].version, .license] | @tsv' <<< "$info" >> "$root/licenses/packages.txt"
  core="https://raw.githubusercontent.com/Homebrew/homebrew-core/$(jq -r .tap_git_head <<< "$info")"
  fetch "$core/$(jq -r .ruby_source_path <<< "$info")" "$sources/recipes/$each.rb" ""
  brew fetch --quiet --build-from-source "$each"
  cp "$(brew --cache --build-from-source "$each")" "$sources/files/$(basename "$(jq -r .urls.stable.url <<< "$info")")"
  jq -r --arg core "$core" '.patches[]? | if .file then [$core + "/" + .file, ""] else [.url, .sha256] end | @tsv' <<< "$info" |
    while IFS=$'\t' read -r url sha256; do
      file="$sources/files/$(basename "$url")"
      [ -e "$file" ] || fetch "$url" "$file" "$sha256"
    done
done
python3 "$here/relocate.py" "$root" "$(brew --prefix)"

while read -r platform sha256 url; do
  [ "$platform" = "$arch" ] || continue
  file="$work/$(basename "$url")"
  fetch "$url" "$file" "$sha256"
  tar -xzf "$file" -C "$root"
done < "$here/pins.txt"

tar -xf "$(ls "$sources"/files/gcc-14.*.tar.*)" -C "$work" '*/COPYING*'
cp "$work"/gcc-*/COPYING* "$root/licenses/"

archive="$out/$name.tar.gz"
tar -czf "$archive" -C "$root" .

test="$work/test"
mkdir -p "$test/unpacked"
tar -xzf "$archive" -C "$test/unpacked"
rm -rf "$root"
cxx="brew/$formula/bin/g++-14"
printf '#include <bits/stdc++.h>\nint main() { std::vector<int> v{3, 1, 2}; std::ranges::sort(v); std::cout << v[0] << v[2] << "\\n"; }\n' > "$test/a.cpp"
SDKROOT="$(xcrun --show-sdk-path)" "$test/unpacked/$cxx" -std=c++23 -O2 -static-libstdc++ -static-libgcc "$test/a.cpp" -o "$test/a"
[ "$("$test/a")" = 13 ]
"$test/unpacked/python/bin/python3" -c 'import sys; assert sys.version_info[:2] == (3, 14)'

jq -n --arg sha256 "$(shasum -a 256 "$archive" | cut -d' ' -f1)" --arg cxx "$cxx" \
  '{sha256: $sha256, cxx: $cxx, python: "python/bin/python3", clangd: "", flags: ["-static-libstdc++", "-static-libgcc"], sdk: true}' > "$out/$name.json"
cat "$out/$name.json"
