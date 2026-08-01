
# Input files for pandoc generation, in the desired order

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = $PSScriptRoot

$inputFiles = @(
    "pandocs_cover_and_config.md", # pandocs_cover_and_config.md should be first since it defines parameters for the entire document as well as the cover page.
    "lists_after_toc.md", # lists_after_toc.md should be second since it places the lists of figures and tables after the table of contents, which is a common convention.
    "Summary.md", # High-Level summary of the module
    "register_map.md", # Register Map for this module
    "appendix.md" # Appendix
)

$outputFile = "Generic_Module.pdf"
$outputPath = Join-Path $scriptRoot $outputFile
$tempDir = Join-Path $scriptRoot ".pandoc_tmp"

# Want table captions to render as above the tables in the markdown,
# but pandocs needs them to be below the tables to render correctly in the PDF.
# This function moves them below the tables before pandoc processes the files.
function Move-TableCaptionsBelow {
    param (
        [string[]]$Lines
    )

    $output = New-Object System.Collections.Generic.List[string]
    $index = 0
    while ($index -lt $Lines.Count) {
        $line = $Lines[$index]
        if ($line -match '^Table:\s*') {
            $caption = $line
            $nextIndex = $index + 1
            while ($nextIndex -lt $Lines.Count -and $Lines[$nextIndex].Trim() -eq "") {
                $nextIndex++
            }
            if ($nextIndex -lt $Lines.Count -and $Lines[$nextIndex].TrimStart().StartsWith("|")) {
                $index = $nextIndex
                while ($index -lt $Lines.Count -and $Lines[$index].TrimStart().StartsWith("|")) {
                    $output.Add($Lines[$index])
                    $index++
                }
                if ($output.Count -gt 0 -and $output[$output.Count - 1].Trim() -ne "") {
                    $output.Add("")
                }
                $output.Add($caption)
                continue
            }
        }

    $output.Add($line)
    $index++
    }

    return $output
}

# Pandoc doesn't support page breaks in markdown, so we use a custom marker and replace it with the appropriate LaTeX command before processing.
function Replace-PagebreakMarkers {
    param (
        [string[]]$Lines
    )

    $updated = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        if ($line.Trim() -eq "<!-- pagebreak -->") {
            if ($updated.Count -gt 0 -and $updated[$updated.Count - 1].Trim() -ne "") {
                $updated.Add("")
            }
            $updated.Add("~~~{=latex}")
            $updated.Add("\newpage")
            $updated.Add("~~~")
            $updated.Add("")
            continue
        }
        $updated.Add($line)
    }

    return $updated
}

foreach ($inputFile in $inputFiles) {
    $inputPath = Join-Path $scriptRoot $inputFile
    if (-not (Test-Path $inputPath)) {
        Write-Error "Input file not found: $inputFile"
        exit 1
    }
}

# Ensure required tools are available
if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) {
    Write-Error "Pandoc is not available on PATH. Install Pandoc and restart your terminal."
    exit 1
}

if (-not (Get-Command xelatex -ErrorAction SilentlyContinue)) {
    Write-Error "XeLaTeX is not available on PATH. Install a TeX distribution (MiKTeX or TeX Live) and restart your terminal."
    exit 1
}

# Ensure required TeX packages are available for XeLaTeX
$unicodeMathPath = & kpsewhich unicode-math.sty 2>$null
if (-not $unicodeMathPath) {
    Write-Error "Missing TeX package 'unicode-math'. Install it via MiKTeX Console or run 'mpm --install=unicode-math', then re-run this script."
    exit 1
}

if (Test-Path $tempDir) {
    Remove-Item -Recurse -Force $tempDir
}
New-Item -ItemType Directory -Path $tempDir | Out-Null

$fontsSource = Join-Path $PSScriptRoot "fonts"
$fontsDest = Join-Path $tempDir "fonts"
if (Test-Path $fontsSource) {
    Copy-Item -Path $fontsSource -Destination $fontsDest -Recurse -Force
}

$tempFiles = @()
foreach ($inputFile in $inputFiles) {
    $tempFile = Join-Path $tempDir $inputFile
    $inputPath = Join-Path $scriptRoot $inputFile
    $lines = Get-Content -Path $inputPath
    $processedLines = Move-TableCaptionsBelow -Lines $lines
    $processedLines = Replace-PagebreakMarkers -Lines $processedLines
    $processedLines | Set-Content -Path $tempFile -Encoding UTF8
    $tempFiles += $tempFile
}

Write-Host "Generating PDF from:`n$($inputFiles -join "`n")"
Push-Location $scriptRoot
try {
    & pandoc @tempFiles -o $outputPath --pdf-engine=xelatex --resource-path=$scriptRoot
    $pandocExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($pandocExitCode -ne 0) {
    Write-Error "Pandoc failed with exit code $pandocExitCode"
    exit $pandocExitCode
}

$resolvedOutputPath = Resolve-Path $outputPath
Write-Host "Wrote $resolvedOutputPath"
