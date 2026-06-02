Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

$RuntimeModule = Import-Module (Join-Path $RepoRoot "src\RuntimeSupport.psm1") -Force -DisableNameChecking -PassThru
Import-Module (Join-Path $RepoRoot "src\Config.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $RepoRoot "src\StateStore.psm1") -Force -DisableNameChecking
$DiagnosticsModule = Import-Module (Join-Path $RepoRoot "src\Diagnostics.psm1") -Force -DisableNameChecking -PassThru
$PowerPolicyModule = Import-Module (Join-Path $RepoRoot "src\PowerPolicy.psm1") -Force -DisableNameChecking -PassThru

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
    $tempDir = Join-Path $env:TEMP ("ll-test-" + [guid]::NewGuid())
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

Invoke-LLTest "Config falls back for invalid numeric values" {
    $tempDir = Join-Path $env:TEMP ("ll-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        $configPath = Join-Path $tempDir "config.json"
        @"
{
  "processNames": ["codex"],
  "pollSeconds": "not-a-number",
  "diagnostics": {
    "eventLookbackHours": "not-a-number"
  }
}
"@ | Set-Content -Path $configPath -Encoding UTF8

        $config = Get-LLConfig -ConfigPath $configPath
        Assert-LLEqual 5 $config.PollSeconds "Invalid pollSeconds should fall back to the default."
        Assert-LLEqual 12 $config.Diagnostics.EventLookbackHours "Invalid eventLookbackHours should fall back to the default."
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-LLTest "Legacy applyOn source flags map to source config" {
    $tempDir = Join-Path $env:TEMP ("ll-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        $configPath = Join-Path $tempDir "config.json"
        @"
{
  "processNames": ["codex"],
  "applyOnAC": false,
  "applyOnDC": true
}
"@ | Set-Content -Path $configPath -Encoding UTF8

        $config = Get-LLConfig -ConfigPath $configPath
        Assert-LLEqual $false $config.AC.Enabled "Legacy applyOnAC should map to ac.enabled."
        Assert-LLEqual $true $config.DC.Enabled "Legacy applyOnDC should map to dc.enabled."
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-LLTest "Policy restore preserves user-modified owned settings" {
    $result = & $PowerPolicyModule {
        $script:FakeValues = @{}
        foreach ($source in @("AC", "DC")) {
            foreach ($settingKey in @("LidAction", "StandbyIdle", "HibernateIdle")) {
                $script:FakeValues["$source/$settingKey"] = 30
            }
        }
        $script:FakeValues["AC/LidAction"] = 1
        $script:FakeValues["AC/StandbyIdle"] = 900
        $script:FakeValues["AC/HibernateIdle"] = 1800

        function Get-LLPowerSettingValue {
            param(
                [string]$SchemeGuid,
                [string]$PowerSource,
                [string]$SettingKey
            )

            $null = $SchemeGuid
            return [int]$script:FakeValues["$PowerSource/$SettingKey"]
        }

        function Set-LLPowerSettingValue {
            param(
                [string]$SchemeGuid,
                [string]$PowerSource,
                [string]$SettingKey,
                [int]$Value
            )

            $null = $SchemeGuid
            $script:FakeValues["$PowerSource/$SettingKey"] = $Value
        }

        $state = [pscustomobject]@{ TouchedSchemes = @() }
        $config = [pscustomobject]@{
            AC = [pscustomobject]@{
                Enabled = $true
                LidCloseDoNothing = $true
                PreventIdleSleep = $true
                PreventHibernate = $true
            }
            DC = [pscustomobject]@{
                Enabled = $false
                LidCloseDoNothing = $true
                PreventIdleSleep = $true
                PreventHibernate = $true
            }
        }

        Enable-LLPolicyProtection -State $state -Config $config -SchemeGuid "scheme" -LogPath $null | Out-Null
        $script:FakeValues["AC/StandbyIdle"] = 600
        Restore-LLPolicyProtection -State $state | Out-Null

        [pscustomobject]@{
            LidAction = $script:FakeValues["AC/LidAction"]
            StandbyIdle = $script:FakeValues["AC/StandbyIdle"]
            HibernateIdle = $script:FakeValues["AC/HibernateIdle"]
            OwnedStandbyIdleAC = [bool]$state.TouchedSchemes[0].OwnedStandbyIdleAC
        }
    }

    Assert-LLEqual 1 $result.LidAction "Owned protected lid action should restore to original value."
    Assert-LLEqual 600 $result.StandbyIdle "User-modified sleep timeout should not be overwritten."
    Assert-LLEqual 1800 $result.HibernateIdle "Owned protected hibernate timeout should restore to original value."
    Assert-LLEqual $false $result.OwnedStandbyIdleAC "Owned flag should clear after restore reconciliation."
}

Invoke-LLTest "Elevation wait policy avoids blocking diagnostics" {
    $startWaits = & $RuntimeModule { param($Command) Test-LLWaitForElevatedCommand -Command $Command } "start"
    $stopWaits = & $RuntimeModule { param($Command) Test-LLWaitForElevatedCommand -Command $Command } "stop"
    $runWaits = & $RuntimeModule { param($Command) Test-LLWaitForElevatedCommand -Command $Command } "run"
    $onceWaits = & $RuntimeModule { param($Command) Test-LLWaitForElevatedCommand -Command $Command } "once"

    Assert-LLTrue $startWaits "start should wait so exit codes can propagate."
    Assert-LLTrue $stopWaits "stop should wait so exit codes can propagate."
    Assert-LLEqual $false $runWaits "run should not block the original non-elevated shell."
    Assert-LLEqual $false $onceWaits "once should not wait for its -NoExit diagnostic window."
}

Invoke-LLTest "Built-in Administrator SID is not treated as unsafe writer" {
    $rid500Unsafe = & $RuntimeModule {
        param($SidText)
        Test-LLUnsafeInstallWriter -IdentityReference $SidText
    } "S-1-5-21-1111111111-2222222222-3333333333-500"
    $everyoneUnsafe = & $RuntimeModule {
        param($SidText)
        Test-LLUnsafeInstallWriter -IdentityReference $SidText
    } "S-1-1-0"

    Assert-LLEqual $false $rid500Unsafe "Built-in Administrator RID 500 should be exempt from unsafe writer detection."
    Assert-LLTrue $everyoneUnsafe "Everyone should be treated as unsafe when it has write access."
}

Invoke-LLTest "User-writable install path is rejected for SYSTEM task registration" {
    $tempDir = Join-Path $env:TEMP ("ll-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        $findingCount = & $RuntimeModule { param($Path) @(Get-LLUnsafeInstallPathAccess -ScriptRoot $Path).Count } $tempDir
        Assert-LLTrue ($findingCount -gt 0) "User-writable temp directory should be reported as unsafe for SYSTEM task registration."
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-LLTest "Legacy state with missing PowerRequest is repaired" {
    $tempDir = Join-Path $env:TEMP ("ll-test-" + [guid]::NewGuid())
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
