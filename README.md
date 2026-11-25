# Toolchains

The compiler and Python that [Eolymp Code](https://github.com/eolymp/code) installs, one archive per system.

- `conda/` builds Linux and Windows: GCC from conda-forge, Python from python-build-standalone and clangd from its releases.
- `macos/` builds macOS: GCC from Homebrew and Python from python-build-standalone.

## Build

    ./conda/build.sh linux-x64    # or linux-arm64, win32-x64; needs micromamba, yq and jq
    ./macos/build.sh              # for the macOS it runs on; needs Homebrew and jq

`out/` gets the archive, a description of it, and the source of its GPL and LGPL parts.

## Licences

The scripts are MIT. Each archive keeps the licences of what it contains in `licenses/`.
