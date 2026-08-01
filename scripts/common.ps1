Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-RepoSetup {
    $requiredVariables = @(
        "REPO_ROOT",
        "SCRIPTS_ROOT",
        "DV_ROOT",
        "RTL_ROOT",
        "LINT_ROOT",
        "SCHEMATICS_ROOT",
        "DOCS_ROOT"
    )

    foreach ($variableName in $requiredVariables) {
        $value = [Environment]::GetEnvironmentVariable($variableName)
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Missing environment variable '$variableName'. Run .\setup.ps1 from the repository root in this PowerShell session first."
        }
    }
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

function Get-PythonCommand {
    foreach ($candidate in @("python", "python3", "py")) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            return $candidate
        }
    }

    throw "Python executable not found. Install Python 3 and ensure python/python3/py is on PATH."
}
