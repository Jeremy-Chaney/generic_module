
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)

$env:REPO_ROOT = $repoRoot
$env:SCRIPTS_ROOT = Join-Path $repoRoot "scripts"
$env:DV_ROOT = Join-Path $repoRoot "dv"
$env:RTL_ROOT = Join-Path $repoRoot "rtl"
$env:LINT_ROOT = Join-Path $repoRoot "lint"
$env:SCHEMATICS_ROOT = Join-Path $repoRoot "schematics"
$env:DOCS_ROOT = Join-Path $repoRoot "docs"

Write-Host "Configured repository environment variables:"
Write-Host "  REPO_ROOT=$env:REPO_ROOT"
Write-Host "  SCRIPTS_ROOT=$env:SCRIPTS_ROOT"
Write-Host "  DV_ROOT=$env:DV_ROOT"
Write-Host "  RTL_ROOT=$env:RTL_ROOT"
Write-Host "  LINT_ROOT=$env:LINT_ROOT"
Write-Host "  SCHEMATICS_ROOT=$env:SCHEMATICS_ROOT"
Write-Host "  DOCS_ROOT=$env:DOCS_ROOT"
