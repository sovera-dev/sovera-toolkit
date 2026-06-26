<#
.SYNOPSIS
    Pulse CLI installer for Windows (PowerShell).

.DESCRIPTION
    Detects the architecture, downloads the matching release archive from the
    public GitHub repo, verifies its SHA256 against the release's checksums.txt
    BEFORE extracting, installs pulse.exe into a per-user directory and adds that
    directory to the user PATH. Mirrors scripts/install.sh for macOS/Linux.

.PARAMETER Version
    Pin a release, e.g. v1.2.0. Defaults to the latest release. Can also be set
    via the PULSE_VERSION environment variable.

.PARAMETER InstallDir
    Where to drop pulse.exe. Defaults to %LOCALAPPDATA%\Programs\pulse. Can also
    be set via the PULSE_INSTALL_DIR environment variable.

.EXAMPLE
    irm https://github.com/sovera-dev/sovera-toolkit/releases/latest/download/install.ps1 | iex

.EXAMPLE
    # The cautious path (review before running):
    irm https://github.com/sovera-dev/sovera-toolkit/releases/latest/download/install.ps1 -OutFile install.ps1
    notepad install.ps1
    .\install.ps1 -Version v1.2.0
#>
[CmdletBinding()]
param(
	[string]$Version = $env:PULSE_VERSION,
	[string]$InstallDir = $env:PULSE_INSTALL_DIR
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # makes Invoke-WebRequest downloads fast

$Repo = 'sovera-dev/sovera-toolkit'
$Binary = 'pulse'

# Default release to install, stamped with the tag by the release pipeline
# (bitbucket-pipelines.yml) when this script is published as a release asset. Left
# as this literal placeholder in the source tree, in which case Resolve-Version
# falls back to querying GitHub for the latest release. -Version / $env:PULSE_VERSION
# always wins.
$VersionDefault = 'v0.1.3'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Done { param([string]$Message) Write-Host "OK  $Message" -ForegroundColor Green }

function Get-Arch {
	switch ($env:PROCESSOR_ARCHITECTURE) {
		'AMD64' { 'amd64' }
		'ARM64' { 'arm64' }
		default { throw "Unsupported architecture: $($env:PROCESSOR_ARCHITECTURE) (released for amd64 and arm64)" }
	}
}

function Resolve-Version {
	if ($Version) { return $Version }
	# Honour the tag stamped into this script at publish time, when present (the
	# source-tree placeholder does not start with "v", so it never matches here).
	if ($VersionDefault -match '^v') { return $VersionDefault }
	$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'pulse-install' }
	if (-not $release.tag_name) {
		throw "Could not determine the latest release; pin one with -Version vX.Y.Z"
	}
	return $release.tag_name
}

function Install-Pulse {
	$arch = Get-Arch
	$tag = Resolve-Version
	$numVersion = $tag.TrimStart('v') # the archive name uses the version without the leading "v"

	$archive = "${Binary}_${numVersion}_windows_${arch}.zip"
	$baseUrl = "https://github.com/$Repo/releases/download/$tag"

	Write-Step "Installing $Binary $tag for windows/$arch"

	$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pulse-install-" + [System.Guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path $tmp -Force | Out-Null
	try {
		$archivePath = Join-Path $tmp $archive
		$checksumsPath = Join-Path $tmp 'checksums.txt'

		Write-Step "Downloading $archive"
		Invoke-WebRequest -Uri "$baseUrl/$archive" -OutFile $archivePath
		Invoke-WebRequest -Uri "$baseUrl/checksums.txt" -OutFile $checksumsPath

		Write-Step "Verifying SHA256 checksum"
		$line = Select-String -Path $checksumsPath -Pattern ([regex]::Escape($archive)) | Select-Object -First 1
		if (-not $line) { throw "No checksum for $archive in checksums.txt" }
		$expected = ($line.Line -split '\s+')[0].ToLower()
		$actual = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLower()
		if ($expected -ne $actual) {
			throw "Checksum mismatch for ${archive}`n  expected: $expected`n  actual:   $actual"
		}

		Write-Step "Extracting"
		Expand-Archive -Path $archivePath -DestinationPath $tmp -Force

		$dir = if ($InstallDir) { $InstallDir } else { Join-Path $env:LOCALAPPDATA "Programs\pulse" }
		New-Item -ItemType Directory -Path $dir -Force | Out-Null
		$dest = Join-Path $dir "$Binary.exe"
		Copy-Item -Path (Join-Path $tmp "$Binary.exe") -Destination $dest -Force
		Write-Done "$Binary installed to $dest"

		Add-ToUserPath -Directory $dir
	}
	finally {
		Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
	}

	Write-Step "Open a new terminal, then run '$Binary version' and '$Binary confluence login'."
}

function Add-ToUserPath {
	param([string]$Directory)
	$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
	$entries = if ($userPath) { $userPath -split ';' } else { @() }
	if ($entries -notcontains $Directory) {
		$newPath = if ($userPath) { "$userPath;$Directory" } else { $Directory }
		[Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
		Write-Step "Added $Directory to your user PATH (restart your terminal to pick it up)."
	}
	# Make it usable in the current session too.
	if (($env:Path -split ';') -notcontains $Directory) {
		$env:Path = "$env:Path;$Directory"
	}
}

Install-Pulse
