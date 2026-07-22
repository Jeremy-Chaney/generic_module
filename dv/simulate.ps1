param(
	[string]$Distro = "Ubuntu"
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

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$rtlFile = Resolve-Path (Join-Path $repoRoot "rtl/generic_module.sv")
$tbFile = Resolve-Path (Join-Path $PSScriptRoot "testbench/tb.sv")

$resultsDir = Join-Path $PSScriptRoot "results"
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

$rtlWsl = Convert-ToWslPath $rtlFile.Path
$tbWsl = Convert-ToWslPath $tbFile.Path
$resultsWsl = Convert-ToWslPath $resultsDir

$bashScript = @"
set -euo pipefail
mkdir -p '$resultsWsl'
cd '$resultsWsl'
iverilog -g2012 -o sim.out '$rtlWsl' '$tbWsl'
vvp sim.out | tee sim.log
"@

Write-Host "Running simulation in WSL distro '$Distro'..."
& wsl -d $Distro -- bash -lc ($bashScript -replace "`r", "")

if ($LASTEXITCODE -ne 0) {
	throw "Simulation failed with exit code $LASTEXITCODE"
}

Write-Host "Simulation completed. Results written to: $resultsDir"
Get-ChildItem -Path $resultsDir | Format-Table -AutoSize

