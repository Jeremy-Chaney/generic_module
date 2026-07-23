param(
    [string]$Top = "generic_module",
    [string]$FileList = "rtl/filelist.f",
  [string]$OutDir = "schematics/web_trace",
    [string]$Distro = "Ubuntu",
    [switch]$NoOpen
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

$repoRoot = Get-RepoRoot -StartDir $PSScriptRoot
$env:GENERIC_MODULE_ROOT = $repoRoot

$fileListPath = if ([System.IO.Path]::IsPathRooted($FileList)) {
    $FileList
} else {
    Join-Path $repoRoot $FileList
}

if (-not (Test-Path $fileListPath -PathType Leaf)) {
    throw "File list not found: $fileListPath"
}

$outDirPath = if ([System.IO.Path]::IsPathRooted($OutDir)) {
    $OutDir
} else {
    Join-Path $repoRoot $OutDir
}

New-Item -ItemType Directory -Path $outDirPath -Force | Out-Null

$repoRootWsl = Convert-ToWslPath $repoRoot
$outDirWsl = Convert-ToWslPath $outDirPath

$synthJsonWsl = "$outDirWsl/$Top.synth.json"
$svgOutWsl = "$outDirWsl/$Top.synth.svg"

$rawFileList = Get-Content -Path $fileListPath -Raw
$rawFileList = $rawFileList -replace '\$\{GENERIC_MODULE_ROOT\}', $repoRootWsl
$rawFileList = $rawFileList -replace '\$GENERIC_MODULE_ROOT', $repoRootWsl

$sourceFiles = New-Object System.Collections.Generic.List[string]
foreach ($rawLine in ($rawFileList -split "`r?`n")) {
    $trimmed = $rawLine.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        continue
    }

    if ($trimmed.StartsWith("#") -or $trimmed.StartsWith("//")) {
        continue
    }

    $withoutHashComment = ($trimmed -split "#", 2)[0].Trim()
    $withoutSlashComment = ($withoutHashComment -split "//", 2)[0].Trim()
    if ([string]::IsNullOrWhiteSpace($withoutSlashComment)) {
        continue
    }

    $sourceFiles.Add($withoutSlashComment)
}

if ($sourceFiles.Count -eq 0) {
    throw "No source files found in file list: $fileListPath"
}

$yosysReadCommands = @($sourceFiles | ForEach-Object { "read_verilog -sv $_" })
# Dummy synthesis path: flatten and map to generic gates for a web-friendly schematic.
$yosysCommand = (@($yosysReadCommands) + "synth -top $Top" + "write_json $synthJsonWsl") -join "; "

$bashScript = @"
set -euo pipefail

if ! command -v yosys >/dev/null 2>&1; then
    echo "Missing dependency: yosys" >&2
    exit 127
fi

if ! command -v netlistsvg >/dev/null 2>&1; then
    echo "Missing dependency: netlistsvg" >&2
    exit 127
fi

export GENERIC_MODULE_ROOT='$repoRootWsl'

yosys -p "$yosysCommand"
netlistsvg '$synthJsonWsl' -o '$svgOutWsl'
"@

Write-Host "GENERIC_MODULE_ROOT=$env:GENERIC_MODULE_ROOT"
Write-Host "Generating synthesized web-trace artifacts for top '$Top' using WSL distro '$Distro'..."

$tempScriptDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gm_web_trace_{0}" -f [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempScriptDir -Force | Out-Null
$tempScriptPath = Join-Path $tempScriptDir "run_web_trace.sh"
Set-Content -Path $tempScriptPath -Value ($bashScript -replace "`r", "") -Encoding ascii

try {
    $tempScriptWsl = Convert-ToWslPath $tempScriptPath
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

$synthJsonPath = Join-Path $outDirPath "$Top.synth.json"
$svgOutPath = Join-Path $outDirPath "$Top.synth.svg"

if (-not (Test-Path -LiteralPath $synthJsonPath -PathType Leaf)) {
    throw "Expected synthesized JSON not found: $synthJsonPath"
}

if (-not (Test-Path -LiteralPath $svgOutPath -PathType Leaf)) {
    $svgCandidates = @(Get-ChildItem -Path $outDirPath -File | Where-Object { $_.Name.StartsWith("$Top.synth.svg") })
    if ($svgCandidates.Count -eq 1) {
        Rename-Item -LiteralPath $svgCandidates[0].FullName -NewName "$Top.synth.svg" -Force
    }
}

if (-not (Test-Path -LiteralPath $svgOutPath -PathType Leaf)) {
    throw "Expected synthesized SVG not found: $svgOutPath"
}

$straySvgFiles = @(Get-ChildItem -Path $outDirPath -File | Where-Object { $_.Name.StartsWith("$Top.synth.svg") -and $_.Name -ne "$Top.synth.svg" })
foreach ($stray in $straySvgFiles) {
  Remove-Item -LiteralPath $stray.FullName -Force
}

$svgInline = Get-Content -Path $svgOutPath -Raw

$htmlPath = Join-Path $outDirPath "$Top.web_trace.html"
$html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Web Trace - $Top</title>
<style>
:root {
  --bg: #0f1115;
  --glow: #1f2530;
  --panel: #181c23;
  --text: #d8dee9;
  --muted: #95a3b8;
  --accent: #6bc46d;
  --warn: #ffd166;
  --hit: #ff8c42;
  --border: #2b3340;
  --border-soft: #2f3948;
  --panel-deep: #0b0e13;
  --row-border: #1e2632;
  --hover: #152131;
  --input-bg: #10151d;
  --button-bg: #17202b;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: "Segoe UI", "Noto Sans", sans-serif;
  background: radial-gradient(1200px 700px at 10% -10%, var(--glow) 10%, var(--bg) 70%);
  color: var(--text);
}
header {
  padding: 12px 16px;
  border-bottom: 1px solid var(--border);
  background: color-mix(in srgb, var(--panel) 92%, transparent);
  position: sticky;
  top: 0;
  backdrop-filter: blur(6px);
}
header h1 {
  margin: 0;
  font-size: 16px;
  font-weight: 700;
}
header p {
  margin: 6px 0 0;
  color: var(--muted);
  font-size: 12px;
}
.controls {
  margin-top: 10px;
  display: flex;
  gap: 8px;
  align-items: center;
  flex-wrap: wrap;
}
.controls input {
  flex: 1;
  min-width: 260px;
  padding: 8px 10px;
  border-radius: 8px;
  border: 1px solid var(--border-soft);
  background: var(--input-bg);
  color: var(--text);
}
.controls button {
  padding: 8px 10px;
  border-radius: 8px;
  border: 1px solid var(--border-soft);
  background: var(--button-bg);
  color: var(--text);
  cursor: pointer;
}
.controls .status {
  font-size: 12px;
  color: var(--muted);
}
.hint {
  margin-top: 6px;
  font-size: 12px;
  color: var(--muted);
}
main { padding: 10px; display: grid; gap: 10px; }
.viewer {
  border: 1px solid var(--border);
  border-radius: 10px;
  overflow: hidden;
  background: var(--panel-deep);
}
.matches {
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--panel-deep);
  max-height: 170px;
  overflow: auto;
}
.match-item {
  width: 100%;
  text-align: left;
  border: 0;
  border-bottom: 1px solid var(--row-border);
  background: transparent;
  color: var(--text);
  padding: 8px 10px;
  cursor: pointer;
}
.match-item:hover { background: var(--hover); }
.match-item:last-child { border-bottom: 0; }
svg {
  width: 100%;
  height: calc(100vh - 280px);
  min-height: 420px;
}
.trace-hit text,
.trace-hit path,
.trace-hit polygon,
.trace-hit ellipse,
.trace-hit rect {
  stroke: var(--hit) !important;
  stroke-width: 2px !important;
}
.trace-selected text,
.trace-selected path,
.trace-selected polygon,
.trace-selected ellipse,
.trace-selected rect {
  stroke: var(--warn) !important;
  stroke-width: 3px !important;
}
.trace-dim {
  opacity: 0.2;
}
[hidden] {
  display: none !important;
}
[data-trace-tone="light"] .kbd {
  background: #e4ecfb;
  border-color: #9eb2d9;
  color: #0f1a2d;
}
[data-trace-tone="normal"] .kbd {
  background: #202938;
  border-color: #46516b;
  color: #d7e4ff;
}
[data-trace-tone="normal"] .modal {
  background: #10151f;
  border-color: #31405a;
  color: #d8dee9;
}
[data-trace-tone="light"] .modal {
  background: #f8fbff;
  border-color: #adc0e2;
  color: #17233a;
}
.overlay {
  position: fixed;
  inset: 0;
  background: rgba(6, 8, 12, 0.56);
  display: grid;
  place-items: center;
  z-index: 50;
}
.modal {
  width: min(520px, calc(100vw - 24px));
  border: 1px solid;
  border-radius: 12px;
  padding: 14px 16px;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.35);
}
.modal h2 {
  margin: 0 0 8px;
  font-size: 16px;
}
.modal p {
  margin: 0 0 12px;
  font-size: 13px;
}
.shortcuts {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 8px 12px;
  align-items: center;
  font-size: 13px;
}
.kbd {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 32px;
  padding: 2px 8px;
  border: 1px solid;
  border-radius: 8px;
  font-family: Consolas, "Courier New", monospace;
  font-size: 12px;
}
[data-trace-tone="light"] .viewer svg text {
  fill: #f1f6ff !important;
}
[data-trace-tone="light"] .viewer svg path,
[data-trace-tone="light"] .viewer svg polygon,
[data-trace-tone="light"] .viewer svg ellipse,
[data-trace-tone="light"] .viewer svg rect,
[data-trace-tone="light"] .viewer svg line {
  stroke: #d9e6ff !important;
}
[data-trace-tone="light"] .viewer svg polygon,
[data-trace-tone="light"] .viewer svg ellipse,
[data-trace-tone="light"] .viewer svg rect {
  fill: color-mix(in srgb, #d9e6ff 10%, transparent) !important;
}
</style>
</head>
<body>
<header>
  <h1>Web Trace: $Top (Dummy Synth)</h1>
  <p>Pan: drag | Zoom: mouse wheel | Click net labels to trace | Source: $Top.synth.svg</p>
  <div class="hint">Keyboard: <span class="kbd">f</span> fit view, <span class="kbd">Esc</span> clear highlight, <span class="kbd">?</span> help</div>
  <div class="controls">
    <input id="netSearch" type="text" placeholder="Find net/signal (substring match)" />
    <button id="clearSearch" type="button">Clear</button>
    <span class="status" id="traceStatus">No filter</span>
  </div>
</header>
<main>
  <div class="matches" id="matchList"></div>
  <div class="viewer" id="viewer">
$svgInline
  </div>
</main>
<div id="shortcutOverlay" class="overlay" hidden>
  <div class="modal" role="dialog" aria-modal="true" aria-labelledby="shortcutTitle" aria-describedby="shortcutDesc">
    <h2 id="shortcutTitle">Shortcut Help</h2>
    <p id="shortcutDesc">Use these shortcuts while browsing the schematic:</p>
    <div class="shortcuts">
      <span class="kbd">f</span><span>Fit to full schematic view</span>
      <span class="kbd">Esc</span><span>Clear search and highlighting</span>
      <span class="kbd">?</span><span>Toggle this help panel</span>
    </div>
  </div>
</div>
<script>
function applyTraceTone(isDarkMode) {
  document.body.setAttribute('data-trace-tone', isDarkMode ? 'light' : 'normal');
}

if (window.matchMedia) {
  var colorSchemeQuery = window.matchMedia('(prefers-color-scheme: dark)');
  applyTraceTone(colorSchemeQuery.matches);
  if (typeof colorSchemeQuery.addEventListener === 'function') {
    colorSchemeQuery.addEventListener('change', function(e){ applyTraceTone(e.matches); });
  } else if (typeof colorSchemeQuery.addListener === 'function') {
    colorSchemeQuery.addListener(function(e){ applyTraceTone(e.matches); });
  }
} else {
  applyTraceTone(false);
}

var viewer = document.getElementById('viewer');
var svg = viewer.querySelector('svg');
var searchInput = document.getElementById('netSearch');
var clearButton = document.getElementById('clearSearch');
var statusEl = document.getElementById('traceStatus');
var matchList = document.getElementById('matchList');
var shortcutOverlay = document.getElementById('shortcutOverlay');

function setOverlayVisible(visible) {
  if (!shortcutOverlay) {
    return;
  }
  shortcutOverlay.hidden = !visible;
}

function toggleOverlay() {
  if (!shortcutOverlay) {
    return;
  }
  setOverlayVisible(shortcutOverlay.hidden);
}

if (shortcutOverlay) {
  shortcutOverlay.addEventListener('click', function(e){
    if (e.target === shortcutOverlay) {
      setOverlayVisible(false);
    }
  });
}

function normalizeLabel(text) {
  return text.replace(/\s+/g, ' ').trim();
}

function clearNodeClasses(nodes) {
  nodes.forEach(function(node){
    node.classList.remove('trace-hit');
    node.classList.remove('trace-selected');
    node.classList.remove('trace-dim');
  });
}

if (svg) {
  var viewBox = svg.viewBox.baseVal;
  if (!viewBox || (viewBox.width === 0 && viewBox.height === 0)) {
    var bb = svg.getBBox();
    svg.setAttribute('viewBox', bb.x + ' ' + bb.y + ' ' + bb.width + ' ' + bb.height);
    viewBox = svg.viewBox.baseVal;
  }

  var state = { dragging: false, x: 0, y: 0 };
  var initialViewBox = null;

  var labelEntries = Array.from(svg.querySelectorAll('text')).map(function(textNode) {
    var label = normalizeLabel(textNode.textContent || '');
    var group = textNode.closest('g') || textNode;
    return {
      label: label,
      labelLower: label.toLowerCase(),
      group: group,
      textNode: textNode
    };
  }).filter(function(entry){ return entry.label.length > 0; });

  var groups = Array.from(new Set(labelEntries.map(function(entry){ return entry.group; })));

  labelEntries.forEach(function(entry){
    entry.textNode.style.cursor = 'pointer';
    entry.textNode.addEventListener('click', function(e){
      e.stopPropagation();
      searchInput.value = entry.label;
      applyFilter(entry.label, true);
    });
  });

  function renderMatchList(uniqueLabels) {
    matchList.innerHTML = '';
    if (uniqueLabels.length === 0) {
      var empty = document.createElement('div');
      empty.className = 'match-item';
      empty.textContent = 'No matches';
      empty.style.cursor = 'default';
      matchList.appendChild(empty);
      return;
    }

    uniqueLabels.slice(0, 120).forEach(function(label){
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'match-item';
      button.textContent = label;
      button.addEventListener('click', function(){
        searchInput.value = label;
        applyFilter(label, true);
      });
      matchList.appendChild(button);
    });
  }

  function applyFilter(rawQuery, exactMode) {
    var query = normalizeLabel(rawQuery || '');
    var queryLower = query.toLowerCase();

    clearNodeClasses(groups);

    if (!queryLower) {
      statusEl.textContent = 'No filter';
      renderMatchList([]);
      return;
    }

    var matches = labelEntries.filter(function(entry){
      return exactMode ? entry.labelLower === queryLower : entry.labelLower.indexOf(queryLower) !== -1;
    });

    var hitGroups = new Set(matches.map(function(entry){ return entry.group; }));
    groups.forEach(function(group){
      if (hitGroups.has(group)) {
        group.classList.add('trace-hit');
      } else {
        group.classList.add('trace-dim');
      }
    });

    if (matches.length > 0) {
      matches[0].group.classList.add('trace-selected');
    }

    var uniqueLabels = Array.from(new Set(matches.map(function(entry){ return entry.label; })));
    renderMatchList(uniqueLabels);
    statusEl.textContent = matches.length.toString() + ' label matches, ' + hitGroups.size.toString() + ' highlighted groups';
  }

  function fitToFullView() {
    if (!initialViewBox) {
      return;
    }

    viewBox.x = initialViewBox.x;
    viewBox.y = initialViewBox.y;
    viewBox.width = initialViewBox.width;
    viewBox.height = initialViewBox.height;
  }

  function clearTraceFilter() {
    searchInput.value = '';
    clearNodeClasses(groups);
    renderMatchList([]);
    statusEl.textContent = 'No filter';
  }

  if (viewBox) {
    initialViewBox = {
      x: viewBox.x,
      y: viewBox.y,
      width: viewBox.width,
      height: viewBox.height
    };
  }

  searchInput.addEventListener('input', function(){
    applyFilter(searchInput.value, false);
  });

  searchInput.addEventListener('keydown', function(e){
    if (e.key === 'Enter') {
      applyFilter(searchInput.value, true);
    }
  });

  clearButton.addEventListener('click', function(){
    clearTraceFilter();
  });

  window.addEventListener('keydown', function(e){
    var tag = (document.activeElement && document.activeElement.tagName) ? document.activeElement.tagName.toLowerCase() : '';
    var isTyping = tag === 'input' || tag === 'textarea';

    if (e.key === '?' || (e.key === '/' && e.shiftKey)) {
      e.preventDefault();
      toggleOverlay();
      return;
    }

    if (e.key === 'Escape') {
      e.preventDefault();
      if (shortcutOverlay && !shortcutOverlay.hidden) {
        setOverlayVisible(false);
        return;
      }
      clearTraceFilter();
      return;
    }

    if (!isTyping && (e.key === 'f' || e.key === 'F')) {
      e.preventDefault();
      fitToFullView();
    }
  });

  renderMatchList([]);

  svg.addEventListener('wheel', function(e){
    e.preventDefault();
    var scale = e.deltaY < 0 ? 0.9 : 1.1;
    var mx = e.offsetX / svg.clientWidth;
    var my = e.offsetY / svg.clientHeight;
    var nw = viewBox.width * scale;
    var nh = viewBox.height * scale;
    viewBox.x += (viewBox.width - nw) * mx;
    viewBox.y += (viewBox.height - nh) * my;
    viewBox.width = nw;
    viewBox.height = nh;
  }, { passive: false });

  svg.addEventListener('mousedown', function(e){
    state.dragging = true;
    state.x = e.clientX;
    state.y = e.clientY;
  });

  window.addEventListener('mouseup', function(){ state.dragging = false; });
  window.addEventListener('mousemove', function(e){
    if (!state.dragging) return;
    var dx = (state.x - e.clientX) * (viewBox.width / svg.clientWidth);
    var dy = (state.y - e.clientY) * (viewBox.height / svg.clientHeight);
    viewBox.x += dx;
    viewBox.y += dy;
    state.x = e.clientX;
    state.y = e.clientY;
  });
}
</script>
</body>
</html>
"@
Set-Content -Path $htmlPath -Value $html -Encoding utf8

Write-Host "Synthesized JSON generated: $synthJsonPath"
Write-Host "Synthesized SVG generated: $svgOutPath"
Write-Host "Web viewer generated: $htmlPath"

if (-not $NoOpen) {
    Start-Process $htmlPath
}
