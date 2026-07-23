param(
    [string]$RegressionList = "sanity_regression",
    [string]$Distro = "Ubuntu",
    [int]$MaxParallel = 2,
    [switch]$StopOnFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($MaxParallel -lt 1) {
    throw "MaxParallel must be at least 1."
}

$dvRoot = (Resolve-Path $PSScriptRoot).Path
$simulateScript = Join-Path $dvRoot "simulate.ps1"
if (-not (Test-Path $simulateScript -PathType Leaf)) {
    throw "simulate.ps1 not found at: $simulateScript"
}

$regressionFilePath = if ([System.IO.Path]::IsPathRooted($RegressionList)) {
    $RegressionList
} else {
    Join-Path $dvRoot $RegressionList
}

if (-not (Test-Path $regressionFilePath -PathType Leaf)) {
    throw "Regression list file not found: $regressionFilePath"
}

$testPaths = New-Object System.Collections.Generic.List[string]
foreach ($rawLine in Get-Content -Path $regressionFilePath) {
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

    $testPaths.Add($withoutSlashComment)
}

if ($testPaths.Count -eq 0) {
    throw "No tests found in regression list: $regressionFilePath"
}

Write-Host "Regression list: $regressionFilePath"
Write-Host "Total tests: $($testPaths.Count)"
Write-Host "Max parallel simulations: $MaxParallel"

$pending = New-Object System.Collections.Queue
foreach ($testPath in $testPaths) {
    $pending.Enqueue($testPath)
}

$runningJobs = New-Object System.Collections.Generic.List[System.Management.Automation.Job]
$results = New-Object System.Collections.Generic.List[object]
$stopQueuing = $false

function Start-SimJob {
    param(
        [Parameter(Mandatory = $true)][string]$JobTestPath,
        [Parameter(Mandatory = $true)][string]$JobSimulateScript,
        [Parameter(Mandatory = $true)][string]$JobDvRoot,
        [Parameter(Mandatory = $true)][string]$JobDistro
    )

    Start-Job -Name $JobTestPath -ScriptBlock {
        param($TestPath, $SimulateScript, $DvRoot, $Distro)

        Set-StrictMode -Version Latest
        $ErrorActionPreference = "Stop"
        Set-Location $DvRoot

        $start = Get-Date
        $output = @()
        $exitCode = 0

        try {
            $output = & $SimulateScript -TestPath $TestPath -Distro $Distro *>&1
            $exitCode = $LASTEXITCODE
            if ($null -eq $exitCode) {
                $exitCode = 0
            }
        }
        catch {
            $output += $_ | Out-String
            $exitCode = 1
        }

        $end = Get-Date

        [pscustomobject]@{
            TestPath = $TestPath
            ExitCode = [int]$exitCode
            StartTime = $start
            EndTime = $end
            DurationSec = [math]::Round(($end - $start).TotalSeconds, 2)
            Output = [string[]]$output
        }
    } -ArgumentList $JobTestPath, $JobSimulateScript, $JobDvRoot, $JobDistro
}

try {
    while ($pending.Count -gt 0 -or $runningJobs.Count -gt 0) {
        while (-not $stopQueuing -and $pending.Count -gt 0 -and $runningJobs.Count -lt $MaxParallel) {
            $nextTest = [string]$pending.Dequeue()
            $job = Start-SimJob -JobTestPath $nextTest -JobSimulateScript $simulateScript -JobDvRoot $dvRoot -JobDistro $Distro
            $runningJobs.Add($job) | Out-Null
            Write-Host "Started: $nextTest"
        }

        if ($runningJobs.Count -eq 0) {
            break
        }

        $finishedJob = Wait-Job -Job $runningJobs.ToArray() -Any -Timeout 2
        if ($null -eq $finishedJob) {
            continue
        }

        $jobResult = Receive-Job -Job $finishedJob
        if ($null -eq $jobResult) {
            $jobResult = [pscustomobject]@{
                TestPath = $finishedJob.Name
                ExitCode = 1
                StartTime = $null
                EndTime = $null
                DurationSec = 0
                Output = @("No output received from job.")
            }
        }

        $results.Add($jobResult) | Out-Null
        $null = $runningJobs.Remove($finishedJob)

        if ($jobResult.ExitCode -eq 0) {
            Write-Host "Passed: $($jobResult.TestPath) ($($jobResult.DurationSec)s)"
        }
        else {
            Write-Host "Failed: $($jobResult.TestPath) ($($jobResult.DurationSec)s)"
            if ($StopOnFailure) {
                $stopQueuing = $true
            }
        }

        Remove-Job -Job $finishedJob -Force
    }
}
finally {
    foreach ($job in $runningJobs) {
        if ($job.State -eq "Running" -or $job.State -eq "NotStarted") {
            Stop-Job -Job $job -Force | Out-Null
        }

        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

$orderedResults = @($results | Sort-Object TestPath)
$passCount = @($orderedResults | Where-Object { $_.ExitCode -eq 0 }).Count
$failResults = @($orderedResults | Where-Object { $_.ExitCode -ne 0 })

Write-Host ""
Write-Host "Regression summary:"
Write-Host "Passed: $passCount"
Write-Host "Failed: $($failResults.Count)"
Write-Host "Total:  $($orderedResults.Count)"

if ($failResults.Count -gt 0) {
    Write-Host ""
    Write-Host "Failure details:"
    foreach ($failure in $failResults) {
        Write-Host ""
        Write-Host "=== $($failure.TestPath) ==="
        foreach ($line in $failure.Output) {
            Write-Host $line
        }
    }

    exit 1
}

exit 0