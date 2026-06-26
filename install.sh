#!/bin/sh
# Pulse CLI installer for macOS and Linux.
#
# Usage:
#   curl -fsSL https://github.com/sovera-dev/sovera-toolkit/releases/latest/download/install.sh | sh
#
# The cautious path (review before running):
#   curl -fsSL https://github.com/sovera-dev/sovera-toolkit/releases/latest/download/install.sh -o install.sh
#   less install.sh
#   sh install.sh
#
# Environment overrides:
#   PULSE_VERSION       Pin a release, e.g. v1.2.0 (default: the latest release).
#   PULSE_INSTALL_DIR   Where to drop the binary (default: ~/.local/bin, or
#                       /usr/local/bin when running as root).
#
# Security: served over HTTPS, the downloaded archive's SHA256 is verified
# against the release's checksums.txt BEFORE it is extracted, and the whole
# body runs inside main() invoked only on the last line, so a truncated
# download fails safely instead of executing half a script (docs/05 §7).
set -eu

REPO="sovera-dev/sovera-toolkit"
BINARY="pulse"

# Default release to install, stamped with the tag by the release pipeline
# (bitbucket-pipelines.yml) when this script is published as a release asset. Left
# as this literal placeholder in the source tree, in which case resolve_version
# falls back to querying GitHub for the latest release. PULSE_VERSION always wins.
PULSE_VERSION_DEFAULT="v0.1.3"

# ANSI styling, disabled when stdout is not a terminal or NO_COLOR is set.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m'); RED=$(printf '\033[31m')
	GREEN=$(printf '\033[32m'); CYAN=$(printf '\033[36m'); RESET=$(printf '\033[0m')
else
	BOLD=; DIM=; RED=; GREEN=; CYAN=; RESET=
fi

info() { printf '%s==>%s %s\n' "$CYAN" "$RESET" "$1" >&2; }
warn() { printf '%swarning:%s %s\n' "$BOLD" "$RESET" "$1" >&2; }
die() { printf '%serror:%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }

# need CMD — abort with a clear message if a required tool is missing.
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

# http_get URL — print the body of URL to stdout using curl or wget.
http_get() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO- "$1"
	else
		die "need either curl or wget to download files"
	fi
}

# http_download URL DEST — save URL to DEST using curl or wget.
http_download() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO "$2" "$1"
	else
		die "need either curl or wget to download files"
	fi
}

# detect_os — map `uname -s` to GoReleaser's GOOS token.
detect_os() {
	os=$(uname -s)
	case "$os" in
		Linux) echo "linux" ;;
		Darwin) echo "darwin" ;;
		*) die "unsupported operating system: $os (this installer covers macOS and Linux; on Windows use install.ps1)" ;;
	esac
}

# detect_arch — map `uname -m` to GoReleaser's GOARCH token.
detect_arch() {
	arch=$(uname -m)
	case "$arch" in
		x86_64 | amd64) echo "amd64" ;;
		aarch64 | arm64) echo "arm64" ;;
		*) die "unsupported architecture: $arch (released for amd64 and arm64)" ;;
	esac
}

# resolve_version — echo the release tag to install, honouring PULSE_VERSION,
# otherwise asking GitHub for the latest release tag.
resolve_version() {
	if [ -n "${PULSE_VERSION:-}" ]; then
		echo "$PULSE_VERSION"
		return
	fi
	# Honour the tag stamped into this script at publish time, when present (the
	# source-tree placeholder does not start with "v", so it never matches here).
	case "$PULSE_VERSION_DEFAULT" in
		v*)
			echo "$PULSE_VERSION_DEFAULT"
			return
			;;
	esac
	# The redirect target of /releases/latest ends in the tag; parse it without
	# needing a JSON tool. Example location: .../releases/tag/v1.2.0
	tag=$(http_get "https://api.github.com/repos/${REPO}/releases/latest" \
		| sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
		| head -n1)
	[ -n "$tag" ] || die "could not determine the latest release; pin one with PULSE_VERSION=vX.Y.Z"
	echo "$tag"
}

# sha256_of FILE — print the file's SHA256 hex digest.
sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{print $1}'
	else
		die "need sha256sum or shasum to verify the download"
	fi
}

# install_dir — echo the target directory, creating it if needed.
install_dir() {
	if [ -n "${PULSE_INSTALL_DIR:-}" ]; then
		echo "$PULSE_INSTALL_DIR"
	elif [ "$(id -u)" -eq 0 ]; then
		echo "/usr/local/bin"
	else
		echo "$HOME/.local/bin"
	fi
}

main() {
	need uname
	need mktemp
	need tar

	os=$(detect_os)
	arch=$(detect_arch)
	version=$(resolve_version)
	num_version=${version#v} # the archive name uses the version without the leading "v"

	archive="${BINARY}_${num_version}_${os}_${arch}.tar.gz"
	base_url="https://github.com/${REPO}/releases/download/${version}"

	info "Installing ${BOLD}${BINARY} ${version}${RESET} for ${os}/${arch}"

	tmp=$(mktemp -d 2>/dev/null || mktemp -d -t pulse-install)
	# shellcheck disable=SC2064
	trap "rm -rf '$tmp'" EXIT INT TERM

	info "Downloading ${DIM}${archive}${RESET}"
	http_download "${base_url}/${archive}" "${tmp}/${archive}" \
		|| die "download failed: ${base_url}/${archive}"
	http_download "${base_url}/checksums.txt" "${tmp}/checksums.txt" \
		|| die "could not download checksums.txt"

	info "Verifying SHA256 checksum"
	expected=$(grep " ${archive}\$" "${tmp}/checksums.txt" | awk '{print $1}' | head -n1)
	[ -n "$expected" ] || die "no checksum for ${archive} in checksums.txt"
	actual=$(sha256_of "${tmp}/${archive}")
	[ "$expected" = "$actual" ] || die "checksum mismatch for ${archive}
  expected: ${expected}
  actual:   ${actual}"

	info "Extracting"
	tar -xzf "${tmp}/${archive}" -C "$tmp" "$BINARY" \
		|| die "could not extract ${BINARY} from the archive"

	dir=$(install_dir)
	mkdir -p "$dir" || die "could not create install directory: $dir"
	install -m 0755 "${tmp}/${BINARY}" "${dir}/${BINARY}" 2>/dev/null \
		|| { cp "${tmp}/${BINARY}" "${dir}/${BINARY}" && chmod 0755 "${dir}/${BINARY}"; } \
		|| die "could not install ${BINARY} into ${dir} (try sudo, or set PULSE_INSTALL_DIR)"

	printf '%s✓%s %s installed to %s%s/%s%s\n' \
		"$GREEN" "$RESET" "$BINARY" "$BOLD" "$dir" "$BINARY" "$RESET" >&2

	case ":${PATH}:" in
		*":${dir}:"*) ;;
		*) warn "${dir} is not on your PATH. Add this to your shell profile:"
			printf '    export PATH="%s:$PATH"\n' "$dir" >&2 ;;
	esac

	info "Run ${BOLD}${BINARY} version${RESET} to confirm, then ${BOLD}${BINARY} confluence login${RESET}."
}

main "$@"
