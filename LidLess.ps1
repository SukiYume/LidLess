#Requires -Version 5.1
<#
.SYNOPSIS
    LidLess keeps configured agent processes usable after laptop lid close.
.DESCRIPTION
    Commands:
      start  - register and start the SYSTEM scheduled-task runner
      stop   - stop/unregister the runner, release requests, and restore policy
      status - print current task, policy, process, and state status
      doctor - print status plus recent power/WLAN diagnostics
      run    - run the monitor loop in this PowerShell process
      once   - execute one protection tick, then print status
#>

param(
    [ValidateSet("start", "stop", "status", "doctor", "run", "once")]
    [string]$Command = "status"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$ScriptPath = $PSCommandPath
$ScriptRoot = Split-Path -Parent $ScriptPath
$SrcRoot = Join-Path $ScriptRoot "src"
$ConfigPath = Join-Path $ScriptRoot "config.json"
$StateDir = Join-Path $ScriptRoot "state"
$StatePath = Join-Path $StateDir "state.json"
$LogDir = Join-Path $ScriptRoot "logs"
$LogPath = Join-Path $LogDir "LidLess.log"
$TaskName = "LidLess"

Import-Module (Join-Path $SrcRoot "RuntimeSupport.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $SrcRoot "Config.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $SrcRoot "ProcessMatcher.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $SrcRoot "NativePower.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $SrcRoot "StateStore.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $SrcRoot "PowerPolicy.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $SrcRoot "ScheduledTask.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $SrcRoot "Diagnostics.psm1") -Force -DisableNameChecking

$Context = [pscustomobject]@{
    ScriptPath = $ScriptPath
    ScriptRoot = $ScriptRoot
    ConfigPath = $ConfigPath
    StatePath = $StatePath
    LogPath = $LogPath
    TaskName = $TaskName
}

function Get-CurrentInputs {
    param($Config)

    $config = if ($null -ne $Config) { $Config } else { Get-LLConfig -ConfigPath $Context.ConfigPath }
    $powerSource = Get-LLPowerSource
    $sourceConfig = Get-LLSourceConfig -Config $config -PowerSource $powerSource
    $matchedProcesses = Get-LLMatchingProcesses -ProcessNames $config.ProcessNames
    $schemeGuid = Get-LLActivePowerSchemeGuid

    return [pscustomobject]@{
        Config = $config
        PowerSource = $powerSource
        SourceConfig = $sourceConfig
        Matches = $matchedProcesses
        SchemeGuid = $schemeGuid
    }
}

function Set-RuntimeState {
    param(
        $State,
        [bool]$Protected,
        [string]$PowerSource,
        $MatchedProcesses,
        [string]$Reason
    )

    $matchText = @($MatchedProcesses | ForEach-Object { Format-LLProcessMatch -Process $_ })
    Set-LLStateRuntime `
        -State $State `
        -Protected $Protected `
        -PowerSource $PowerSource `
        -MatchText $matchText `
        -Reason $Reason `
        -PowerRequestState (Get-LLPowerRequestState)
}

function Test-RuntimeLogChange {
    param(
        $State,
        [bool]$Protected,
        [string]$PowerSource,
        [string]$Reason
    )

    if ($null -eq $State -or $null -eq $State.Runtime) {
        return $true
    }

    if ([bool]$State.Runtime.Protected -ne $Protected) {
        return $true
    }
    if ([string]$State.Runtime.PowerSource -ne $PowerSource) {
        return $true
    }
    if ([string]$State.Runtime.Reason -ne $Reason) {
        return $true
    }

    return $false
}

function Restore-AllProtection {
    param(
        [switch]$RemoveStateFile,
        [string]$Reason = "restore"
    )

    Clear-LLPowerRequest
    $state = Read-LLState -StatePath $Context.StatePath
    $restored = Restore-LLPolicyProtection -State $state
    if ($restored) {
        Write-LLLog -LogPath $Context.LogPath -Message "Policy protection restored. Reason=$Reason"
    }
    Set-RuntimeState -State $state -Protected $false -PowerSource (Get-LLPowerSource) -MatchedProcesses @() -Reason $Reason

    if ($RemoveStateFile) {
        Remove-LLState -StatePath $Context.StatePath
    }
    else {
        Save-LLState -StatePath $Context.StatePath -State $state
    }
}

function Invoke-MonitorTick {
    param($Config)

    $inputs = Get-CurrentInputs -Config $Config
    $state = Read-LLState -StatePath $Context.StatePath
    $hasMatches = @($inputs.Matches).Count -gt 0
    $currentSourceEnabled = [bool]$inputs.SourceConfig.Enabled

    if ($hasMatches -and $currentSourceEnabled) {
        $runtimeReason = "matched process and source enabled"
        $shouldLog = Test-RuntimeLogChange -State $state -Protected $true -PowerSource $inputs.PowerSource -Reason $runtimeReason

        Enable-LLPolicyProtection `
            -State $state `
            -Config $inputs.Config `
            -SchemeGuid $inputs.SchemeGuid `
            -LogPath $Context.LogPath | Out-Null

        $reason = "LidLess: protected agent process is running"
        Set-LLPowerRequest `
            -Reason $reason `
            -SystemRequired ([bool]$inputs.SourceConfig.HoldSystemRequiredRequest) `
            -ExecutionRequired ([bool]$inputs.SourceConfig.HoldExecutionRequiredRequest)

        Set-RuntimeState `
            -State $state `
            -Protected $true `
            -PowerSource $inputs.PowerSource `
            -MatchedProcesses $inputs.Matches `
            -Reason $runtimeReason

        Save-LLState -StatePath $Context.StatePath -State $state

        if ($shouldLog) {
            $names = @($inputs.Matches | ForEach-Object { Format-LLProcessMatch -Process $_ }) -join ", "
            Write-LLLog -LogPath $Context.LogPath -Message "Protected active. Source=$($inputs.PowerSource), Matches=$names"
        }
        return
    }

    Clear-LLPowerRequest
    $restored = Restore-LLPolicyProtection -State $state

    $reason = if ($hasMatches) {
        "matched process but current source $($inputs.PowerSource) is disabled"
    }
    else {
        "no matched process"
    }

    $shouldLog = Test-RuntimeLogChange -State $state -Protected $false -PowerSource $inputs.PowerSource -Reason $reason

    Set-RuntimeState `
        -State $state `
        -Protected $false `
        -PowerSource $inputs.PowerSource `
        -MatchedProcesses $inputs.Matches `
        -Reason $reason

    Save-LLState -StatePath $Context.StatePath -State $state
    if ($restored) {
        Write-LLLog -LogPath $Context.LogPath -Message "Policy protection restored. Reason=$reason"
    }
    if ($shouldLog) {
        Write-LLLog -LogPath $Context.LogPath -Message "Protection inactive. Reason=$reason"
    }
}

function Start-MonitorLoop {
    Ensure-LLAdmin -ScriptPath $Context.ScriptPath -Command "run"
    Write-LLLog -LogPath $Context.LogPath -Message "Monitor loop started."

    $consecutiveFailures = 0
    $maxConsecutiveFailures = 5

    while ($true) {
        try {
            $config = Get-LLConfig -ConfigPath $Context.ConfigPath
            Invoke-MonitorTick -Config $config
            $consecutiveFailures = 0
            Start-Sleep -Seconds $config.PollSeconds
        }
        catch {
            $consecutiveFailures++
            Write-LLLog -LogPath $Context.LogPath -Message "Monitor tick failed ($consecutiveFailures/$maxConsecutiveFailures): $($_.Exception.Message)"
            if ($consecutiveFailures -ge $maxConsecutiveFailures) {
                Write-LLLog -LogPath $Context.LogPath -Message "Monitor exiting after $consecutiveFailures consecutive tick failures so the scheduled task can restart it."
                try {
                    Restore-AllProtection -Reason "monitor failure threshold"
                }
                catch {
                    Write-LLLog -LogPath $Context.LogPath -Message "Failed to restore protection before monitor restart: $($_.Exception.Message)"
                }
                exit 1
            }
            Start-Sleep -Seconds 10
        }
    }
}

function Start-LidLess {
    Ensure-LLAdmin -ScriptPath $Context.ScriptPath -Command "start"
    Assert-LLTrustedInstallPath -ScriptRoot $Context.ScriptRoot
    $config = Get-LLConfig -ConfigPath $Context.ConfigPath
    $previousTaskState = Get-LLTaskState -TaskName $Context.TaskName

    Stop-LLTask -TaskName $Context.TaskName

    if (Test-Path $Context.StatePath) {
        Restore-AllProtection -RemoveStateFile -Reason "start cleanup"
        Write-LLLog -LogPath $Context.LogPath -Message "Recovered residual state before start. PreviousTaskState=$previousTaskState"
    }

    Register-LLTask -TaskName $Context.TaskName -ScriptPath $Context.ScriptPath
    Start-LLTask -TaskName $Context.TaskName

    Write-LLLog -LogPath $Context.LogPath -Message "Service started. PollSeconds=$($config.PollSeconds)"
    Write-Host "LidLess started as SYSTEM scheduled task '$($Context.TaskName)'."
}

function Stop-LidLess {
    Ensure-LLAdmin -ScriptPath $Context.ScriptPath -Command "stop"

    Stop-LLTask -TaskName $Context.TaskName
    Unregister-LLTask -TaskName $Context.TaskName
    Restore-AllProtection -RemoveStateFile -Reason "service stopped"

    Write-LLLog -LogPath $Context.LogPath -Message "Service stopped and policy restored."
    Write-Host "LidLess stopped, power requests released, and touched settings restored."
}

function Show-Status {
    $config = Get-LLConfig -ConfigPath $Context.ConfigPath
    $state = Read-LLState -StatePath $Context.StatePath
    $schemeGuid = Get-LLActivePowerSchemeGuid
    $snapshot = Get-LLPowerPolicySnapshot -SchemeGuid $schemeGuid
    $powerSource = Get-LLPowerSource
    $sourceConfig = Get-LLSourceConfig -Config $config -PowerSource $powerSource
    $matchedProcesses = Get-LLMatchingProcesses -ProcessNames $config.ProcessNames
    $taskState = Get-LLTaskState -TaskName $Context.TaskName

    Write-LLStatus `
        -TaskName $Context.TaskName `
        -TaskState $taskState `
        -PowerSource $powerSource `
        -SourceConfig $sourceConfig `
        -SchemeGuid $schemeGuid `
        -Snapshot $snapshot `
        -Config $config `
        -MatchedProcesses $matchedProcesses `
        -State $state
}

function Write-LLEventLines {
    param($Events)

    foreach ($record in @($Events)) {
        Write-Host ("    {0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f $record.TimeCreated, $record.Id, $record.Summary)
    }
}

function Show-Doctor {
    Show-Status
    $config = Get-LLConfig -ConfigPath $Context.ConfigPath
    Write-Host ""
    Write-Host "Diagnostics"
    Write-Host "  Available sleep states:"
    Get-LLSleepStates | ForEach-Object { Write-Host "    $_" }
    Write-Host ""
    Write-Host "  powercfg /requests:"
    Get-LLPowerRequestsText | ForEach-Object { Write-Host "    $_" }
    if ([bool]$config.Diagnostics.IncludeRecentPowerEvents) {
        Write-Host ""
        Write-Host "  Recent power events:"
        Write-LLEventLines -Events (Get-LLRecentPowerEvents -Hours $config.Diagnostics.EventLookbackHours)
    }
    Write-Host ""
    Write-Host "  Recent WLAN events:"
    Write-LLEventLines -Events (Get-LLRecentWlanEvents -Hours $config.Diagnostics.EventLookbackHours)
}

switch ($Command) {
    "start" { Start-LidLess }
    "stop" { Stop-LidLess }
    "status" { Show-Status }
    "doctor" { Show-Doctor }
    "run" { Start-MonitorLoop }
    "once" {
        Ensure-LLAdmin -ScriptPath $Context.ScriptPath -Command "once"
        Invoke-MonitorTick
        # A one-shot diagnostic command must not leave process-scoped power requests open.
        Clear-LLPowerRequest
        $state = Read-LLState -StatePath $Context.StatePath
        Set-LLStatePowerRequest -State $state -PowerRequestState (Get-LLPowerRequestState)
        Save-LLState -StatePath $Context.StatePath -State $state
        Show-Status
    }
}
