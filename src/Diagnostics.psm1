Set-StrictMode -Version 2.0

function Format-LLLidAction {
    param([int]$Value)

    switch ($Value) {
        0 { return "0 (Do nothing)" }
        1 { return "1 (Sleep)" }
        2 { return "2 (Hibernate)" }
        3 { return "3 (Shutdown)" }
        default { return "$Value (Unknown)" }
    }
}

function Write-LLStatus {
    param(
        [string]$TaskName,
        [string]$TaskState,
        [string]$PowerSource,
        $SourceConfig,
        [string]$SchemeGuid,
        $Snapshot,
        $Config,
        $MatchedProcesses,
        $State
    )

    Write-Host "LidLess status"
    Write-Host "  Task:                 $TaskName ($TaskState)"
    Write-Host "  Power source:         $PowerSource"
    Write-Host "  Source enabled:       $($SourceConfig.Enabled)"
    Write-Host "  Active scheme:        $SchemeGuid"
    Write-Host "  AC lid:               $(Format-LLLidAction -Value ([int]$Snapshot.AC.LidAction))"
    Write-Host "  DC lid:               $(Format-LLLidAction -Value ([int]$Snapshot.DC.LidAction))"
    Write-Host "  AC sleep after:       $(Format-LLDurationSeconds -Seconds ([int]$Snapshot.AC.StandbyIdle))"
    Write-Host "  DC sleep after:       $(Format-LLDurationSeconds -Seconds ([int]$Snapshot.DC.StandbyIdle))"
    Write-Host "  AC hibernate after:   $(Format-LLDurationSeconds -Seconds ([int]$Snapshot.AC.HibernateIdle))"
    Write-Host "  DC hibernate after:   $(Format-LLDurationSeconds -Seconds ([int]$Snapshot.DC.HibernateIdle))"
    Write-Host "  Poll seconds:         $($Config.PollSeconds)"
    Write-Host "  Process names:        $($Config.ProcessNames -join ', ')"

    if (@($MatchedProcesses).Count -gt 0) {
        $matchText = @($MatchedProcesses | ForEach-Object { Format-LLProcessMatch -Process $_ }) -join ", "
        Write-Host "  Matches:              $matchText"
    }
    else {
        Write-Host "  Matches:              none"
    }

    Write-Host "  Runtime protected:    $($State.Runtime.Protected)"
    Write-Host "  Runtime reason:       $($State.Runtime.Reason)"
    if ($State.Runtime.LastHeartbeatAt) {
        Write-Host "  Runtime heartbeat:    $($State.Runtime.LastHeartbeatAt) (pid=$($State.Runtime.MonitorProcessId))"
    }
    if ([bool]$State.Runtime.Protected -and $TaskState -notin @("Running", "Access denied")) {
        Write-Host "  Runtime warning:      protected state is present but task is not running; run start or stop to reconcile policy."
    }
    Write-Host "  Runtime power request: handle=$($State.Runtime.PowerRequest.HasHandle), system=$($State.Runtime.PowerRequest.SystemRequired), execution=$($State.Runtime.PowerRequest.ExecutionRequired)"
}

function Get-LLSleepStates {
    $output = & powercfg /availablesleepstates 2>&1
    return @($output | Where-Object { $_ -ne "" })
}

function Get-LLPowerRequestsText {
    try {
        $output = & powercfg /requests 2>&1
        return @($output | Where-Object { $_ -ne "" })
    }
    catch {
        return @("powercfg /requests unavailable in this shell: $($_.Exception.Message)")
    }
}

function Convert-LLEventSummary {
    param($Record)

    $message = ($Record.Message -replace "\r?\n", " " -replace "\s+", " ").Trim()
    if ($message.Length -gt 180) {
        $message = $message.Substring(0, 180) + "..."
    }

    return [pscustomobject]@{
        TimeCreated = $Record.TimeCreated
        Id = $Record.Id
        Summary = $message
    }
}

function Get-LLDiagnosticStartTime {
    param([int]$Hours)

    return (Get-Date).AddHours(-1 * [Math]::Max(1, $Hours))
}

function Get-LLRecentPowerEvents {
    param([int]$Hours = 12)

    $start = Get-LLDiagnosticStartTime -Hours $Hours
    $ids = 42, 107, 187, 506, 507, 566, 41, 172
    return @(Get-WinEvent -FilterHashtable @{LogName = "System"; StartTime = $start} -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -eq "Microsoft-Windows-Kernel-Power" -and $_.Id -in $ids } |
        Sort-Object TimeCreated -Descending |
        Select-Object -First 20 |
        ForEach-Object { Convert-LLEventSummary -Event $_ })
}

function Get-LLRecentWlanEvents {
    param([int]$Hours = 12)

    $start = Get-LLDiagnosticStartTime -Hours $Hours
    return @(Get-WinEvent -FilterHashtable @{LogName = "Microsoft-Windows-WLAN-AutoConfig/Operational"; StartTime = $start} -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -in 8000, 8001, 8002, 8003, 11000, 11001, 11004, 11005 } |
        Sort-Object TimeCreated -Descending |
        Select-Object -First 20 |
        ForEach-Object { Convert-LLEventSummary -Event $_ })
}

Export-ModuleMember -Function Write-LLStatus, Get-LLSleepStates, Get-LLPowerRequestsText, Get-LLRecentPowerEvents, Get-LLRecentWlanEvents
