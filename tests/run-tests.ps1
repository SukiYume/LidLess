Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

Import-Module (Join-Path $RepoRoot "src\RuntimeSupport.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $RepoRoot "src\Config.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $RepoRoot "src\StateStore.psm1") -Force -DisableNameChecking
$DiagnosticsModule = Import-Module (Join-Path $RepoRoot "src\Diagnostics.psm1") -Force -DisableNameChecking -PassThru

$script:Passed = 0

function Assert-LLTrue {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-LLEqual {
    param(
        $Expected,
        $Actual,
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Invoke-LLTest {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    & $Body
    $script:Passed++
    Write-Host "[pass] $Name"
}

Invoke-LLTest "PowerShell files parse" {
    $allErrors = @()
    Get-ChildItem -Path $RepoRoot -Recurse -Include *.ps1, *.psm1 | ForEach-Object {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors) {
            $allErrors += $parseErrors | ForEach-Object { "$($_.Extent.File):$($_.Extent.StartLineNumber): $($_.Message)" }
        }
    }

    Assert-LLEqual 0 $allErrors.Count ($allErrors -join [Environment]::NewLine)
}

Invoke-LLTest "Default config focuses on task-like agent processes" {
    $config = New-LLDefaultConfig
    Assert-LLEqual "claude,codex" ($config.ProcessNames -join ",") "Unexpected default process names."
}

Invoke-LLTest "Diagnostic event summaries normalize event records" {
    $record = [pscustomobject]@{
        TimeCreated = [datetime]"2026-06-02T10:17:00"
        Id = 507
        Message = "Line one`r`n  Line two"
    }

    $summary = & $DiagnosticsModule { param($EventRecord) Convert-LLEventSummary -Record $EventRecord } $record
    Assert-LLEqual 507 $summary.Id "Unexpected event id."
    Assert-LLEqual "Line one Line two" $summary.Summary "Event summary was not normalized."
}

Invoke-LLTest "Status explains access-limited scheduled task state" {
    $snapshot = [pscustomobject]@{
        AC = [pscustomobject]@{
            LidAction = 0
            StandbyIdle = 0
            HibernateIdle = 0
        }
        DC = [pscustomobject]@{
            LidAction = 1
            StandbyIdle = 1800
            HibernateIdle = 1800
        }
    }
    $config = [pscustomobject]@{
        PollSeconds = 5
        ProcessNames = @("codex")
    }
    $state = [pscustomobject]@{
        Runtime = [pscustomobject]@{
            Protected = $true
            Reason = "matched process and source enabled"
            LastHeartbeatAt = "2026-06-02T13:00:00+08:00"
            MonitorProcessId = 1234
            PowerRequest = [pscustomobject]@{
                HasHandle = $true
                SystemRequired = $true
                ExecutionRequired = $true
            }
        }
    }

    $output = & {
        Write-LLStatus `
            -TaskName "LidLess" `
            -TaskState "Access denied" `
            -PowerSource "AC" `
            -SourceConfig ([pscustomobject]@{ Enabled = $true }) `
            -SchemeGuid "381b4222-f694-41f0-9685-ff5bb260df2e" `
            -Snapshot $snapshot `
            -Config $config `
            -MatchedProcesses @() `
            -State $state
    } 6>&1 | Out-String

    Assert-LLTrue ($output -match "Shell elevated:\s+(True|False)") "Status did not print shell elevation state."
    Assert-LLTrue ($output -match "exact scheduled-task state requires an elevated shell") "Status did not explain access-limited task state."
}

Invoke-LLTest "Config normalizes exe suffix and de-duplicates case-insensitively" {
    $tempDir = Join-Path $env:TEMP ("alg-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        $configPath = Join-Path $tempDir "config.json"
        @"
{
  "processNames": ["codex.exe", "Codex", " claude "],
  "pollSeconds": 1,
  "ac": { "enabled": true },
  "dc": { "enabled": false }
}
"@ | Set-Content -Path $configPath -Encoding UTF8

        $config = Get-LLConfig -ConfigPath $configPath
        Assert-LLEqual "codex,claude" ($config.ProcessNames -join ",") "Process names were not normalized."
        Assert-LLEqual 2 $config.PollSeconds "PollSeconds should be clamped to minimum."
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-LLTest "Legacy state with missing PowerRequest is repaired" {
    $tempDir = Join-Path $env:TEMP ("alg-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        $statePath = Join-Path $tempDir "state.json"
        @"
{
  "Runtime": {
    "Protected": true,
    "PowerSource": "AC",
    "Matches": [],
    "Reason": "legacy"
  },
  "TouchedSchemes": []
}
"@ | Set-Content -Path $statePath -Encoding UTF8

        $state = Read-LLState -StatePath $statePath
        Assert-LLTrue ($state.Runtime.PSObject.Properties.Name -contains "PowerRequest") "PowerRequest was not added."
        Assert-LLTrue ($state.Runtime.PowerRequest.PSObject.Properties.Name -contains "HasHandle") "HasHandle was not added."
        Assert-LLTrue ($state.Runtime.PSObject.Properties.Name -contains "LastHeartbeatAt") "LastHeartbeatAt was not added."
        Assert-LLTrue ($state.Runtime.PSObject.Properties.Name -contains "MonitorProcessId") "MonitorProcessId was not added."
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-LLTest "Process match formatting is shared" {
    $process = [pscustomobject]@{
        ProcessName = "codex"
        Id = 1234
    }

    Assert-LLEqual "codex[1234]" (Format-LLProcessMatch -Process $process) "Unexpected match text."
}

Write-Host "All tests passed ($script:Passed)."
