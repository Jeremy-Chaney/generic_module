param(
    [string]$Distro = "Ubuntu",
    [switch]$DryRun
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

$bashScript = @'
set -euo pipefail

have_yosys=0
have_netlistsvg=0
have_node=0
have_npm=0

if command -v yosys >/dev/null 2>&1; then
    have_yosys=1
fi

if command -v netlistsvg >/dev/null 2>&1; then
    have_netlistsvg=1
fi

if command -v node >/dev/null 2>&1; then
    have_node=1
fi

if command -v npm >/dev/null 2>&1; then
    have_npm=1
fi

if [ "$have_yosys" -eq 1 ] && [ "$have_netlistsvg" -eq 1 ]; then
    echo "All web-trace dependencies are already installed (yosys, netlistsvg)."
    exit 0
fi

echo "Installing missing web-trace dependencies..."
export DEBIAN_FRONTEND=noninteractive

need_apt=0
apt_packages=()

if [ "$have_yosys" -eq 0 ]; then
    need_apt=1
    apt_packages+=(yosys)
fi

if [ "$have_netlistsvg" -eq 0 ] && { [ "$have_node" -eq 0 ] || [ "$have_npm" -eq 0 ]; }; then
    need_apt=1
    if [ "$have_node" -eq 0 ]; then
        apt_packages+=(nodejs)
    fi
    if [ "$have_npm" -eq 0 ]; then
        apt_packages+=(npm)
    fi
fi

if [ "$need_apt" -eq 1 ]; then
    sudo apt-get update
    sudo apt-get install -y "${apt_packages[@]}"
fi

if ! command -v netlistsvg >/dev/null 2>&1; then
    sudo npm install -g netlistsvg
fi

echo "Done. Installed tools:"
command -v yosys || true
command -v netlistsvg || true
'@

$tempScriptDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gm_install_schematic_{0}" -f [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempScriptDir -Force | Out-Null
$tempScriptPath = Join-Path $tempScriptDir "install_schematic_tools.sh"
Set-Content -Path $tempScriptPath -Value ($bashScript -replace "`r", "") -Encoding ascii

try {
    $tempScriptWsl = Convert-ToWslPath $tempScriptPath

    if ($DryRun) {
        Write-Host "Dry run enabled. The following script would run in WSL distro '$Distro':"
        Write-Host ""
        Get-Content -Path $tempScriptPath
        exit 0
    }

    Write-Host "Installing web-trace dependencies in WSL distro '$Distro'..."
    & wsl -d $Distro -- bash $tempScriptWsl
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
finally {
    if (Test-Path $tempScriptDir -PathType Container) {
        Remove-Item -Path $tempScriptDir -Recurse -Force
    }
}

Write-Host "Web-trace tool install completed successfully."
