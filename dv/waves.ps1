param(
    [string]$TestPath = "tests/basic_test",
    [string]$Distro = "Ubuntu",
    [ValidateSet("wayland", "x11")]
    [string]$Backend = "x11"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    param([Parameter(Mandatory = $true)][string]$StartDir)

    $gitOutput = & git -C $StartDir rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitOutput)) {
        return $gitOutput.Trim()
    }

    throw "Could not resolve git repository root from: $StartDir"
}

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

function Resolve-TestSelection {
    param(
        [Parameter(Mandatory = $true)][string]$RelativeTestPath,
        [Parameter(Mandatory = $true)][string]$DvRoot
    )

    $absoluteTestPath = Join-Path $DvRoot $RelativeTestPath
    if (Test-Path $absoluteTestPath -PathType Container) {
        $resolvedTestDir = (Resolve-Path $absoluteTestPath).Path
        $resolvedTestFile = Join-Path $resolvedTestDir "test.sv"
        $relativeOutputPath = $RelativeTestPath
    } elseif (Test-Path $absoluteTestPath -PathType Leaf) {
        $resolvedTestFile = (Resolve-Path $absoluteTestPath).Path
        $resolvedTestDir = Split-Path $resolvedTestFile -Parent
        $relativeOutputPath = Split-Path $RelativeTestPath -Parent
    } else {
        throw "Test path not found: $RelativeTestPath"
    }

    if (-not (Test-Path $resolvedTestFile -PathType Leaf)) {
        throw "Test file not found: $resolvedTestFile"
    }

    if ([string]::IsNullOrWhiteSpace($relativeOutputPath)) {
        $relativeOutputPath = "test"
    }

    [pscustomobject]@{
        TestDir = $resolvedTestDir
        OutputRelativePath = $relativeOutputPath
    }
}

$repoRoot = Get-RepoRoot -StartDir $PSScriptRoot
$env:GENERIC_MODULE_ROOT = $repoRoot

$dvRoot = Join-Path $env:GENERIC_MODULE_ROOT "dv"
if (-not (Test-Path $dvRoot -PathType Container)) {
    throw "Expected dv directory not found under GENERIC_MODULE_ROOT: $dvRoot"
}

$testSelection = Resolve-TestSelection -RelativeTestPath $TestPath -DvRoot $dvRoot
$wavePath = Join-Path $dvRoot (Join-Path "results" $testSelection.OutputRelativePath)
$wavePath = Join-Path $wavePath "tb.vcd"
$wavePath = Resolve-Path $wavePath -ErrorAction Stop
$waveWsl = Convert-ToWslPath $wavePath.Path

$bashScript = @"
set -euo pipefail
if [ ! -f '$waveWsl' ]; then
    echo 'Waveform file not found: $waveWsl' >&2
    exit 1
fi
env GDK_BACKEND='$Backend' gtkwave '$waveWsl'
"@

Write-Host "Opening waveform for test path '$TestPath' in GTKWave from WSL distro '$Distro' using backend '$Backend'..."
& wsl -d $Distro -- bash -lc ($bashScript -replace "`r", "")

if ($LASTEXITCODE -ne 0) {
    throw "GTKWave failed with exit code $LASTEXITCODE"
}

Write-Host "GTKWave exited cleanly."
