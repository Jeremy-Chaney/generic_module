param(
    [string]$Distro = "Ubuntu"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$commonScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\scripts\common.ps1"))
if (-not (Test-Path $commonScript -PathType Leaf)) {
    throw "Shared helper script not found: $commonScript"
}
. $commonScript
Assert-RepoSetup

$generatorScript = Join-Path $env:SCRIPTS_ROOT "gen_register_artifacts.py"
if (Test-Path $generatorScript -PathType Leaf) {
    Write-Host "Regenerating register artifacts from CSV..."
    $pythonCmd = Get-PythonCommand
    & $pythonCmd $generatorScript
    if ($LASTEXITCODE -ne 0) {
        throw "Register artifact generation failed."
    }
}

$repoRootWsl = Convert-ToWslPath $env:REPO_ROOT
$lintScriptWsl = "$repoRootWsl/lint/run_verilator_lint.sh"

$bashScript = @"
set -euo pipefail
bash '$lintScriptWsl'
"@

Write-Host "Running Verilator lint in WSL distro '$Distro'..."
& wsl -d $Distro -- bash -lc ($bashScript -replace "`r", "")
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
