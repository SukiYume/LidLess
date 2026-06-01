#Requires -Version 5.1
<#
.SYNOPSIS
    AgentLidGuard keeps configured agent processes usable after laptop lid close.
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
$LogPath = Join-Path $LogDir "AgentLidGuard.log"
$TaskName = "AgentLidGuard"

Import-Module (Join-Path $SrcRoot "Common.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $SrcRoot "Config.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $SrcRoot "ProcessWatch.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $SrcRoot "NativePower.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $SrcRoot "StateStore.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $SrcRoot "PowerPolicy.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $SrcRoot "TaskService.psm1") -Force -DisableNameChecking
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
    $config = Get-ALGConfig -ConfigPath $Context.ConfigPath
    $powerSource = Get-ALGPowerSource
    $sourceConfig = Get-ALGSourceConfig -Config $config -PowerSource $powerSource
    $matchedProcesses = Get-ALGMatchingProcesses -ProcessNames $config.ProcessNames
    $schemeGuid = Get-ALGActivePowerSchemeGuid

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
        $Matches,
        [string]$Reason
    )

    $matchText = @($Matches | ForEach-Object { Format-ALGProcessMatch -Process $_ })
    Set-ALGStateRuntime `
        -State $State `
        -Protected $Protected `
        -PowerSource $PowerSource `
        -Matches $matchText `
        -Reason $Reason `
        -PowerRequestState (Get-ALGPowerRequestState)
}

function Restore-AllProtection {
    param(
        [switch]$RemoveStateFile,
        [string]$Reason = "restore"
    )

    Clear-ALGPowerRequest
    $state = Read-ALGState -StatePath $Context.StatePath
    Restore-ALGPolicyProtection -State $state | Out-Null
    Set-RuntimeState -State $state -Protected $false -PowerSource (Get-ALGPowerSource) -Matches @() -Reason $Reason

    if ($RemoveStateFile) {
        Remove-ALGState -StatePath $Context.StatePath
    }
    else {
        Save-ALGState -StatePath $Context.StatePath -State $state
    }
}

function Invoke-MonitorTick {
    $inputs = Get-CurrentInputs
    $state = Read-ALGState -StatePath $Context.StatePath
    $hasMatches = @($inputs.Matches).Count -gt 0
    $currentSourceEnabled = [bool]$inputs.SourceConfig.Enabled

    if ($hasMatches -and $currentSourceEnabled) {
        Enable-ALGPolicyProtection `
            -State $state `
            -Config $inputs.Config `
            -SchemeGuid $inputs.SchemeGuid `
            -LogPath $Context.LogPath | Out-Null

        $reason = "AgentLidGuard: protected agent process is running"
        Set-ALGPowerRequest `
            -Reason $reason `
            -SystemRequired ([bool]$inputs.SourceConfig.HoldSystemRequiredRequest) `
            -ExecutionRequired ([bool]$inputs.SourceConfig.HoldExecutionRequiredRequest)

        Set-RuntimeState `
            -State $state `
            -Protected $true `
            -PowerSource $inputs.PowerSource `
            -Matches $inputs.Matches `
            -Reason "matched process and source enabled"

        Save-ALGState -StatePath $Context.StatePath -State $state

        $names = @($inputs.Matches | ForEach-Object { Format-ALGProcessMatch -Process $_ }) -join ", "
        Write-ALGLog -LogPath $Context.LogPath -Message "Protected active. Source=$($inputs.PowerSource), Matches=$names"
        return
    }

    Clear-ALGPowerRequest
    Restore-ALGPolicyProtection -State $state | Out-Null

    $reason = if ($hasMatches) {
        "matched process but current source $($inputs.PowerSource) is disabled"
    }
    else {
        "no matched process"
    }

    Set-RuntimeState `
        -State $state `
        -Protected $false `
        -PowerSource $inputs.PowerSource `
        -Matches $inputs.Matches `
        -Reason $reason

    Save-ALGState -StatePath $Context.StatePath -State $state
    Write-ALGLog -LogPath $Context.LogPath -Message "Protection inactive. Reason=$reason"
}

function Start-MonitorLoop {
    Ensure-ALGAdmin -ScriptPath $Context.ScriptPath -Command "run"
    Write-ALGLog -LogPath $Context.LogPath -Message "Monitor loop started."

    $consecutiveFailures = 0
    $maxConsecutiveFailures = 5

    while ($true) {
        try {
            $config = Get-ALGConfig -ConfigPath $Context.ConfigPath
            Invoke-MonitorTick
            $consecutiveFailures = 0
            Start-Sleep -Seconds $config.PollSeconds
        }
        catch {
            $consecutiveFailures++
            Write-ALGLog -LogPath $Context.LogPath -Message "Monitor tick failed ($consecutiveFailures/$maxConsecutiveFailures): $($_.Exception.Message)"
            if ($consecutiveFailures -ge $maxConsecutiveFailures) {
                Write-ALGLog -LogPath $Context.LogPath -Message "Monitor exiting after $consecutiveFailures consecutive tick failures so the scheduled task can restart it."
                try {
                    Restore-AllProtection -Reason "monitor failure threshold"
                }
                catch {
                    Write-ALGLog -LogPath $Context.LogPath -Message "Failed to restore protection before monitor restart: $($_.Exception.Message)"
                }
                exit 1
            }
            Start-Sleep -Seconds 10
        }
    }
}

function Start-AgentLidGuard {
    Ensure-ALGAdmin -ScriptPath $Context.ScriptPath -Command "start"
    $config = Get-ALGConfig -ConfigPath $Context.ConfigPath
    $previousTaskState = Get-ALGTaskState -TaskName $Context.TaskName

    if (Test-Path $Context.StatePath) {
        Restore-AllProtection -RemoveStateFile -Reason "start cleanup"
        Write-ALGLog -LogPath $Context.LogPath -Message "Recovered residual state before start. PreviousTaskState=$previousTaskState"
    }

    Register-ALGTask -TaskName $Context.TaskName -ScriptPath $Context.ScriptPath
    Start-ALGTask -TaskName $Context.TaskName

    Write-ALGLog -LogPath $Context.LogPath -Message "Service started. PollSeconds=$($config.PollSeconds)"
    Write-Host "AgentLidGuard started as SYSTEM scheduled task '$($Context.TaskName)'."
}

function Stop-AgentLidGuard {
    Ensure-ALGAdmin -ScriptPath $Context.ScriptPath -Command "stop"

    Stop-ALGTask -TaskName $Context.TaskName
    Unregister-ALGTask -TaskName $Context.TaskName
    Restore-AllProtection -RemoveStateFile -Reason "service stopped"

    Write-ALGLog -LogPath $Context.LogPath -Message "Service stopped and policy restored."
    Write-Host "AgentLidGuard stopped, power requests released, and touched settings restored."
}

function Show-Status {
    $config = Get-ALGConfig -ConfigPath $Context.ConfigPath
    $state = Read-ALGState -StatePath $Context.StatePath
    $schemeGuid = Get-ALGActivePowerSchemeGuid
    $snapshot = Get-ALGPowerPolicySnapshot -SchemeGuid $schemeGuid
    $powerSource = Get-ALGPowerSource
    $sourceConfig = Get-ALGSourceConfig -Config $config -PowerSource $powerSource
    $matchedProcesses = Get-ALGMatchingProcesses -ProcessNames $config.ProcessNames
    $taskState = Get-ALGTaskState -TaskName $Context.TaskName

    Write-ALGStatus `
        -TaskName $Context.TaskName `
        -TaskState $taskState `
        -PowerSource $powerSource `
        -SourceConfig $sourceConfig `
        -SchemeGuid $schemeGuid `
        -Snapshot $snapshot `
        -Config $config `
        -Matches $matchedProcesses `
        -State $state
}

function Show-Doctor {
    Show-Status
    $config = Get-ALGConfig -ConfigPath $Context.ConfigPath
    Write-Host ""
    Write-Host "Diagnostics"
    Write-Host "  Available sleep states:"
    Get-ALGSleepStates | ForEach-Object { Write-Host "    $_" }
    Write-Host ""
    Write-Host "  powercfg /requests:"
    Get-ALGPowerRequestsText | ForEach-Object { Write-Host "    $_" }
    if ([bool]$config.Diagnostics.IncludeRecentPowerEvents) {
        Write-Host ""
        Write-Host "  Recent power events:"
        Get-ALGRecentPowerEvents -Hours $config.Diagnostics.EventLookbackHours | ForEach-Object {
            Write-Host ("    {0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f $_.TimeCreated, $_.Id, $_.Summary)
        }
    }
    Write-Host ""
    Write-Host "  Recent WLAN events:"
    Get-ALGRecentWlanEvents -Hours $config.Diagnostics.EventLookbackHours | ForEach-Object {
        Write-Host ("    {0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f $_.TimeCreated, $_.Id, $_.Summary)
    }
}

switch ($Command) {
    "start" { Start-AgentLidGuard }
    "stop" { Stop-AgentLidGuard }
    "status" { Show-Status }
    "doctor" { Show-Doctor }
    "run" { Start-MonitorLoop }
    "once" {
        Ensure-ALGAdmin -ScriptPath $Context.ScriptPath -Command "once"
        Invoke-MonitorTick
        Clear-ALGPowerRequest
        $state = Read-ALGState -StatePath $Context.StatePath
        Set-ALGStatePowerRequest -State $state -PowerRequestState (Get-ALGPowerRequestState)
        Save-ALGState -StatePath $Context.StatePath -State $state
        Show-Status
    }
}
