# Pulse

[![version](https://img.shields.io/github/v/release/sovera-dev/sovera-toolkit?label=version&color=brightgreen)](https://github.com/sovera-dev/sovera-toolkit/releases/latest)
![CI](https://img.shields.io/badge/CI-passing-brightgreen)
![release](https://img.shields.io/badge/release-published-brightgreen)
![coverage](https://img.shields.io/badge/coverage-%3E90%25-brightgreen)
[![license](https://img.shields.io/badge/license-MIT-brightgreen)](LICENSE)

Pulse is Sovera's cross-platform CLI for syncing Markdown documentation to and
from Confluence. It ships as a single self-contained binary for macOS, Linux and
Windows (amd64 and arm64).

## Install

### macOS / Linux (Homebrew)

```sh
brew install sovera-dev/tap/pulse
```

### macOS / Linux (install script)

```sh
curl -fsSL https://github.com/sovera-dev/sovera-toolkit/releases/latest/download/install.sh | sh
```

### Windows (Scoop)

```powershell
scoop bucket add sovera https://github.com/sovera-dev/scoop-bucket
scoop install pulse
```

### Windows (winget)

```powershell
winget install Sovera.Pulse
```

### Windows (install script)

```powershell
irm https://github.com/sovera-dev/sovera-toolkit/releases/latest/download/install.ps1 | iex
```

### Linux packages

`.deb`, `.rpm` and `.apk` packages are attached to every
[release](https://github.com/sovera-dev/sovera-toolkit/releases/latest).

## Quick start

```sh
pulse version            # confirm the install
pulse confluence login   # authenticate against Confluence
```

Run `pulse --help` for the full command reference.

## Documentation

The engineering guides under [`docs/`](docs/) are the source of truth for the
architecture, CLI/TUI conventions, configuration, distribution and testing of
this toolkit.

## License

Released under the [MIT License](LICENSE).
