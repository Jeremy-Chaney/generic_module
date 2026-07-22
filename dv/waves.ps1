param(
    [string]$Distro = "Ubuntu",
    [string]$WaveFile = "results/tb.vcd",
    [ValidateSet("wayland", "x11")]
    [string]$Backend = "wayland"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToWslPath {
    param([Parameter(Mandatory = $true)][string]$WindowsPath)

    $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
    $normalized = $fullPath -replace "\\", "/"

    if ($normalized -match "^([A-Za-z]):/(.*)$") {
        $drive = $matches[1].ToLowerInvariant()
        $rest = $matches[2]
        return "/mnt/$drive/$rest"
    }

    throw "Unable to convert Windows path to WSL path: $WindowsPath"
}

$wavePath = Resolve-Path (Join-Path $PSScriptRoot $WaveFile) -ErrorAction Stop
$waveWsl = Convert-ToWslPath $wavePath.Path

$bashScript = @"
set -euo pipefail
if [ ! -f '$waveWsl' ]; then
    echo 'Waveform file not found: $waveWsl' >&2
    exit 1
fi
env GDK_BACKEND='$Backend' gtkwave '$waveWsl'
"@

Write-Host "Opening waveform in GTKWave from WSL distro '$Distro' using backend '$Backend'..."
& wsl -d $Distro -- bash -lc ($bashScript -replace "`r", "")

if ($LASTEXITCODE -ne 0) {
    throw "GTKWave failed with exit code $LASTEXITCODE"
}

Write-Host "GTKWave exited cleanly."
