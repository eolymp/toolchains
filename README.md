# Toolchains

The compiler and Python that [Eolymp Code](https://github.com/eolymp/code) installs, one archive per system.

- `linux/` takes GCC from conda-forge, Python from python-build-standalone and clangd from its releases.

## Build

    ./linux/build.sh x64    # or arm64; needs micromamba, yq and jq

`out/` gets the archive, a description of it, and the source of its GPL and LGPL parts.

## Licences

The scripts are MIT. Each archive keeps the licences of what it contains in `licenses/`.
