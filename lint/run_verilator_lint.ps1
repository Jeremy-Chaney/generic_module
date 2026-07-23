param(
    [string]$Distro = "Ubuntu"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (& git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    throw "Could not resolve repository root from: $PSScriptRoot"
}

$repoRootWsl = "/mnt/$($repoRoot[0].ToString().ToLowerInvariant())/$($repoRoot.Substring(3) -replace '\\','/')"
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
