param(
	[string]$TestPath = "tests/basic_test",
	[string]$Distro = "Ubuntu"
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
		TestFile = $resolvedTestFile
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

$tbFileList = Resolve-Path (Join-Path $dvRoot "testbench/TB.f")
$tbDir = Resolve-Path (Join-Path $dvRoot "testbench")

$resultsDir = Join-Path $dvRoot (Join-Path "results" $testSelection.OutputRelativePath)
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

$dvRootWsl = Convert-ToWslPath $dvRoot
$repoRootWsl = Convert-ToWslPath $env:GENERIC_MODULE_ROOT
$tbFileListWsl = Convert-ToWslPath $tbFileList.Path
$tbDirWsl = Convert-ToWslPath $tbDir.Path
$testDirWsl = Convert-ToWslPath $testSelection.TestDir
$resultsWsl = Convert-ToWslPath $resultsDir

$resolvedFileList = Join-Path $tbDir.Path "TB.resolved.f"
$rawFileList = Get-Content -Path $tbFileList.Path -Raw
$rawFileList = $rawFileList -replace '\$\{GENERIC_MODULE_ROOT\}', $repoRootWsl
$rawFileList = $rawFileList -replace '\$GENERIC_MODULE_ROOT', $repoRootWsl
Set-Content -Path $resolvedFileList -Value $rawFileList -Encoding ascii
$resolvedFileListWsl = Convert-ToWslPath $resolvedFileList

$bashScript = @"
set -euo pipefail
export GENERIC_MODULE_ROOT='$repoRootWsl'
mkdir -p '$resultsWsl'
cd '$dvRootWsl'
iverilog -g2012 -I '$tbDirWsl' -I '$testDirWsl' -f '$resolvedFileListWsl' -o '$resultsWsl/sim.out' 2> '$resultsWsl/compile.err' || {
	grep -v '^I give up\.$' '$resultsWsl/compile.err' >&2 || true
	exit 2
}
cd '$resultsWsl'
vvp sim.out | tee sim.log
"@

Write-Host "GENERIC_MODULE_ROOT=$env:GENERIC_MODULE_ROOT"
Write-Host "Running simulation for test path '$TestPath' in WSL distro '$Distro'..."
& wsl -d $Distro -- bash -lc ($bashScript -replace "`r", "")

if ($LASTEXITCODE -ne 0) {
	Write-Host "Syntax Error in simulation"
	exit $LASTEXITCODE
}

Write-Host "Simulation completed. Results written to: $resultsDir"
Get-ChildItem -Path $resultsDir | Format-Table -AutoSize

