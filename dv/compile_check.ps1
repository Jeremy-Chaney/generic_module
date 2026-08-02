param(
    [string]$TestPath = "tests/basic_test",
    [string]$Distro = "Ubuntu",
    [switch]$SkipRegisterGeneration,
    [switch]$RegenerateRegisters
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$setupScript = Join-Path $repoRoot "setup.ps1"
$commonScript = Join-Path $repoRoot "scripts/common.ps1"

if (-not (Test-Path $setupScript -PathType Leaf)) {
    throw "Repository setup script not found: $setupScript"
}
if (-not (Test-Path $commonScript -PathType Leaf)) {
    throw "Shared helper script not found: $commonScript"
}

. $setupScript
. $commonScript
Assert-RepoSetup

function Resolve-TestSelection {
    param(
        [Parameter(Mandatory = $true)][string]$RelativeOrAbsoluteTestPath,
        [Parameter(Mandatory = $true)][string]$DvRoot
    )

    $candidatePath = if ([System.IO.Path]::IsPathRooted($RelativeOrAbsoluteTestPath)) {
        [System.IO.Path]::GetFullPath($RelativeOrAbsoluteTestPath)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $DvRoot $RelativeOrAbsoluteTestPath))
    }

    if (Test-Path $candidatePath -PathType Container) {
        $resolvedTestDir = (Resolve-Path $candidatePath).Path
        $resolvedTestFile = Join-Path $resolvedTestDir "test.sv"
    }
    elseif (Test-Path $candidatePath -PathType Leaf) {
        $resolvedTestFile = (Resolve-Path $candidatePath).Path
        $resolvedTestDir = Split-Path $resolvedTestFile -Parent
    }
    else {
        throw "Test path not found: $RelativeOrAbsoluteTestPath"
    }

    if (-not (Test-Path $resolvedTestFile -PathType Leaf)) {
        throw "Test file not found: $resolvedTestFile"
    }

    $dvRootNormalized = [System.IO.Path]::GetFullPath($DvRoot).TrimEnd('\\')
    $testDirNormalized = [System.IO.Path]::GetFullPath($resolvedTestDir)
    if (-not $testDirNormalized.StartsWith($dvRootNormalized, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Test path must be under DV root: $DvRoot"
    }

    $relativeOutputPath = $testDirNormalized.Substring($dvRootNormalized.Length).TrimStart('\\')
    if ([string]::IsNullOrWhiteSpace($relativeOutputPath)) {
        $relativeOutputPath = "test"
    }

    [pscustomobject]@{
        TestDir = $resolvedTestDir
        TestFile = $resolvedTestFile
        OutputRelativePath = $relativeOutputPath
    }
}

$shouldGenerateRegisters = $false
if ($PSBoundParameters.ContainsKey("SkipRegisterGeneration")) {
    $shouldGenerateRegisters = -not $SkipRegisterGeneration
}
if ($PSBoundParameters.ContainsKey("RegenerateRegisters")) {
    $shouldGenerateRegisters = $RegenerateRegisters
}

$generatorScript = Join-Path $env:SCRIPTS_ROOT "gen_register_artifacts.py"
if ($shouldGenerateRegisters -and (Test-Path $generatorScript -PathType Leaf)) {
    Write-Host "Regenerating register artifacts from CSV..."
    $pythonCmd = Get-PythonCommand
    & $pythonCmd $generatorScript
    if ($LASTEXITCODE -ne 0) {
        throw "Register artifact generation failed."
    }
}

$dvRoot = $env:DV_ROOT
if (-not (Test-Path $dvRoot -PathType Container)) {
    throw "Expected dv directory not found under DV_ROOT: $dvRoot"
}

$testSelection = Resolve-TestSelection -RelativeOrAbsoluteTestPath $TestPath -DvRoot $dvRoot

$tbFileList = Resolve-Path (Join-Path $dvRoot "testbench/TB.f")
$tbDir = Resolve-Path (Join-Path $dvRoot "testbench")

$resultsDir = Join-Path $dvRoot (Join-Path "results/compile_checks" $testSelection.OutputRelativePath)
if (Test-Path $resultsDir -PathType Container) {
    Remove-Item -Path $resultsDir -Recurse -Force
}
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

$dvRootWsl = Convert-ToWslPath $dvRoot
$repoRootWsl = Convert-ToWslPath $env:REPO_ROOT
$tbDirWsl = Convert-ToWslPath $tbDir.Path
$testDirWsl = Convert-ToWslPath $testSelection.TestDir
$resultsWsl = Convert-ToWslPath $resultsDir

$tempFileListDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gm_tb_filelist_{0}" -f [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempFileListDir -Force | Out-Null
Copy-Item -Path (Join-Path $tbDir.Path "*.f") -Destination $tempFileListDir -Force

$resolvedFileList = Join-Path $tempFileListDir "TB.resolved.f"
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
"@

Write-Host "Running compile check for test path '$TestPath' in WSL distro '$Distro'..."
try {
    & wsl -d $Distro -- bash -lc ($bashScript -replace "`r", "")
    if ($LASTEXITCODE -ne 0) {
        throw "Compile check failed with exit code $LASTEXITCODE"
    }
}
finally {
    if (Test-Path $tempFileListDir -PathType Container) {
        Remove-Item -Path $tempFileListDir -Recurse -Force
    }
}

Write-Host "Compile check passed. Output artifacts: $resultsDir"
