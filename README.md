# generic_module

SystemVerilog RTL and DV workspace for running module-level simulations with Icarus Verilog in WSL.

## Repository Structure

```text
generic_module/
├── setup.ps1           # Required to run before using any tools (sets up environment variables)
├── .dvt/               # DVT setup folder
├── docs/               # Pandocs documentation generation script
├── dv/                 # Verification and simulation assets
├── lint/               # Verilator Lint flow
├── rtl/                # RTL source files
├── schematics/         # Web schematic trace flow
└── scripts/            # Commonly used scripts
```

## Prerequisites

- Windows with WSL installed
- A WSL distro (default used by script: `Ubuntu`)
- Icarus Verilog installed in WSL (`iverilog`, `vvp`)
- Optional: GTKWave for viewing VCD files

## Setup Links

- WSL install (Microsoft): [https://learn.microsoft.com/windows/wsl/install]
- WSL commands and distro management (Microsoft): [https://learn.microsoft.com/windows/wsl/basic-commands]
- Ubuntu on WSL documentation (Canonical): [https://documentation.ubuntu.com/wsl/latest/]
- Icarus Verilog documentation: [https://steveicarus.github.io/iverilog/]
- GTKWave project page: [https://gtkwave.sourceforge.net/]

### Tested Setup (Compatible With This Repo)

PowerShell:

```powershell
wsl --install -d Ubuntu
```

Ubuntu shell:

```bash
sudo apt update
sudo apt install -y iverilog gtkwave
iverilog -V
gtkwave --version
```

This DV flow is validated with Ubuntu under WSL and tools installed from Ubuntu apt.

## VS Code Verilog/SystemVerilog Navigation

This repository includes workspace settings for HDL source detection and extension recommendations so you can use Ctrl+click navigation (Go to Definition / Find References) in RTL and DV files.

Recommended open-source VS Code extension:

- `eirikpre.systemverilog` (primary language support for navigation)

Optional companion extension:

- `chipsalliance.verible` (formatting and lint-oriented tooling)

After installing extensions:

1. Reload the VS Code window (`Developer: Reload Window`).
2. Open a file such as `rtl/generic_module.sv` and Ctrl+click a module instance or signal reference.
3. Use `Shift+F12` for references and `F12` for definition navigation.

If navigation is not available yet, close and reopen the workspace folder so the extension can rescan project files.

Workspace indexing is scoped to RTL and DV source trees and excludes generated outputs (`dv/results`, `schematics/web_trace`, `.venv`, `.git`, and `docs`) to improve symbol resolution performance.

If you add new HDL source folders, update `systemverilog.includeIndexing` in `.vscode/settings.json`.

To reduce duplicate references from multiple directed tests, indexing includes only one active test file by default (`dv/tests/basic_test/test.sv`). If you are working on another test, change that single entry in `.vscode/settings.json` (for example to `dv/tests/w1c_test/test.sv`) and reload VS Code.

### Run And Debug Compile Check

This repository includes VS Code Run and Debug entries in `.vscode/launch.json` for compile-only checks (no `vvp` execution).

Available launch configs:

- `SV Compile Check`

Calls `dv/compile_check.ps1`, which reuses `dv/testbench/TB.f` and compiles with Icarus (`iverilog`) in WSL. Compile artifacts are written under:

- `dv/results/compile_checks/...`

Use this flow when you want a quick compile/syntax gate from the Run and Debug panel.

By default, this compile check does not regenerate register artifacts. If needed, run `dv/compile_check.ps1 -RegenerateRegisters` from a terminal.

### DVT

Though it is not an open-source tool, this repository also contains the baseline hooks to use [DVT from AMIQ](https://marketplace.visualstudio.com/items?itemName=amiq.dvt). This is useful for navigating design hierarchies. If it's possible to acquire licenses to use the tool, this extension is recommended for navigating Verilog/SystemVerilog code in this workspace. Educational licenses are likely available.

## Initialize PowerShell Session

Before running the PowerShell helper scripts in this repo, initialize the shared path environment once per PowerShell session from the repository root:

```powershell
.\setup.ps1
```

This exports `REPO_ROOT`, `SCRIPTS_ROOT`, `DV_ROOT`, `RTL_ROOT`, `LINT_ROOT`, `SCHEMATICS_ROOT`, and `DOCS_ROOT` for the current shell.

## Run Simulations

From the repository root:

```powershell
.\setup.ps1
cd .\dv
```

Run default test (`tests/basic_test`):

```powershell
.\simulate.ps1
```

Run a specific test directory:

```powershell
.\simulate.ps1 tests/submodule_test
```

Run a regression list (line-delimited test paths, supports comments and blank lines):

```powershell
.\run_regression.ps1
```

Run a custom regression list with parallel workers:

```powershell
.\run_regression.ps1 -RegressionList sanity_regression -MaxParallel 4
```

Stop launching new tests after the first failure:

```powershell
.\run_regression.ps1 -RegressionList sanity_regression -MaxParallel 4 -StopOnFailure
```

Run with a different WSL distro:

```powershell
.\simulate.ps1 tests/basic_test -Distro Ubuntu
```

## Register Generation Flow

The register block source `rtl/config_registers.sv` is generated from the CSV source of truth:

- `scripts/register_map.csv`

Use this command from repository root to regenerate RTL and docs:

```powershell
python scripts/gen_register_artifacts.py
```

Generated outputs:

- `rtl/config_registers.sv`
- `docs/register_map.md`

Register documentation table:

- `docs/register_map.md`

Supported field access behaviors in the CSV:

- `RO`
- `RW`
- `W1C` (with hardware-set signal support)

Do not hand-edit generated files. Update `scripts/register_map.csv`, rerun the generator, and commit generated artifacts in the same change.

## Generate Documentation PDF

The repository includes a PowerShell-based PDF generation flow for the module specification document.

Local prerequisites:

- Pandoc
- XeLaTeX (MiKTeX or TeX Live)
- Schematic SVG generation from `rtl/filelist.f` if you want the embedded schematic image to refresh before building the PDF

Run from repository root:

```powershell
.\docs\docs_gen.ps1
```

Generated output:

- `docs/Generic_Module.pdf`

The docs flow preprocesses the Markdown inputs before running Pandoc so that table captions and explicit pagebreak markers render correctly in the PDF.
It also regenerates the schematic image used by [docs/Summary.md](docs/Summary.md) before the PDF build in GitHub Actions.

### Publish Docs From GitHub (Artifact + Release)

You can generate the PDF directly from GitHub Actions and publish it on the repository page.

Workflow file:

- `.github/workflows/docs-generation.yml`

How to run:

Automatic run:

1. Open a PR targeting `main` with changes under `docs/`, `scripts/register_map.csv`, or `scripts/gen_register_artifacts.py`.
2. Merge the PR.
3. The workflow runs on PR close, gated to merged PRs only.

Manual run:

1. Go to Actions -> `Documentation PDF` -> `Run workflow`.
2. Leave `create_release=true` to publish the PDF to a release tag.
3. Choose `release_tag` (default: `docs-latest`).

What gets published:

- Workflow artifact: `generic-module-docs-pdf`
- Release asset on the selected tag:
  - `Generic_Module.pdf`

The workflow regenerates `docs/register_map.md` from `scripts/register_map.csv` before building the PDF so the published document always includes fresh register documentation.

## Web Schematic Trace Flow

This repository maintains a single schematic tracing flow based on a lightweight Yosys synthesis and a local HTML viewer.

Install web-trace dependencies in WSL (Ubuntu default):

```powershell
.\setup.ps1
cd .\schematics
.\install_schematic_tools.ps1
```

Preview install actions without changing the system:

```powershell
.\setup.ps1
.\schematics\install_schematic_tools.ps1 -DryRun
```

Generate and open the web schematic trace:

```powershell
.\setup.ps1
.\schematics\web_trace.ps1
```

Generate without opening the browser:

```powershell
.\setup.ps1
.\schematics\web_trace.ps1 -NoOpen
```

Use a different top module:

```powershell
.\setup.ps1
.\schematics\web_trace.ps1 -Top generic_submodule
```

Generated artifacts are written to:

- `schematics/results/web_trace/`

Typical files:

- `generic_module.synth.json`
- `generic_module.synth.svg`
- `generic_module.web_trace.html`

Viewer interactions:

- Pan: mouse drag
- Zoom: mouse wheel
- Net search: type in the search box
- Keyboard shortcuts:
  - `f`: fit full view
  - `Esc`: clear highlighting/search
  - `?`: toggle shortcut help panel

### Publish From GitHub (Artifact + Release)

You can generate the schematic directly from GitHub Actions and publish it on the repository page.

Workflow file:

- `.github/workflows/schematic-web-trace.yml`

How to run:

Automatic run:

1. Open a PR targeting `main` with changes under `rtl/` or `schematics/`.
2. Merge the PR.
3. The workflow runs on PR close, gated to merged PRs only.

Manual run:

1. Go to Actions -> `Schematic Web Trace` -> `Run workflow`.
2. Set `top_module` (default: `generic_module`).
3. Leave `create_release=true` to publish release assets.
4. Choose `release_tag` (default: `schematic-latest`).

What gets published:

- Workflow artifact: `web-trace-<top_module>`
- Release assets on the selected tag:
  - `<top_module>.synth.json`
  - `<top_module>.synth.svg`
  - `<top_module>.web_trace.html`

## Lint RTL With Verilator

This repository contains a basic lint setup to catch:

- Port width mismatches
- Port direction mismatches

This tool does NOT support

- Clock Domain Crossing (CDC) checks
- Reset Domain Crossing (RDC) checks

Install Verilator in Ubuntu/WSL:

```bash
sudo apt update
sudo apt install -y verilator
```

Run lint from Ubuntu/WSL:

```bash
cd /path/to/generic_module
bash lint/run_verilator_lint.sh
```

Run lint from PowerShell (invokes WSL):

```powershell
.\setup.ps1
.\lint\run_verilator_lint.ps1
```

Clean generated test results:

```powershell
.\setup.ps1
.\dv\simulate.ps1 -Clean
```

## Output Locations

Simulation results are written under:

- `dv/results/tests/<test_name>/`

Typical outputs include:

- `sim.out`: compiled simulation executable generated by `iverilog`
- `sim.log`: runtime output from `vvp` (for example VCD open message and simulation finish time)
- `compile.err`: compiler diagnostics from `iverilog` (empty on clean compile)
- `tb.vcd`: waveform dump file generated by the testbench (can be several MB, depending on dump scope/time)

## Notes

- `simulate.ps1` resolves repository paths for WSL and launches compile/run inside Linux.
- The first argument is positional test path. It can be either a test folder (containing `test.sv`) or a direct `test.sv` file path relative to `dv`.
- `run_regression.ps1` reads a regression list (for example `dv/sanity_regression`) and runs listed tests through `simulate.ps1` in parallel.

**Not yet supported:**

- Synthesis
  - Investigating [Yosys](https://yosyshq.net/yosys/about.html) as an open-source synthesis tool
- STA
  - Investigating [OpenSTA](https://github.com/The-OpenROAD-Project/OpenSTA) as an open-source STA tool
- LEC
  - Not much open-source support, may re-use Yosys
- ATPG
  - Minimal much open-source tools
  - Yosys should be able to insert scan chains
- UPF
  - Doesn't look to be supported anywhere
  - This project be keeping everything in one power domain for now
