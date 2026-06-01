Set-StrictMode -Version 2.0

function Format-ALGLidAction {
    param([int]$Value)

    switch ($Value) {
        0 { return "0 (Do nothing)" }
        1 { return "1 (Sleep)" }
        2 { return "2 (Hibernate)" }
        3 { return "3 (Shutdown)" }
        default { return "$Value (Unknown)" }
    }
}

function Write-ALGStatus {
    param(
        [string]$TaskName,
        [string]$TaskState,
        [string]$PowerSource,
        $SourceConfig,
        [string]$SchemeGuid,
        $Snapshot,
        $Config,
        $Matches,
        $State
    )

    Write-Host "AgentLidGuard status"
    Write-Host "  Task:                 $TaskName ($TaskState)"
    Write-Host "  Power source:         $PowerSource"
    Write-Host "  Source enabled:       $($SourceConfig.Enabled)"
    Write-Host "  Active scheme:        $SchemeGuid"
    Write-Host "  AC lid:               $(Format-ALGLidAction -Value ([int]$Snapshot.AC.LidAction))"
    Write-Host "  DC lid:               $(Format-ALGLidAction -Value ([int]$Snapshot.DC.LidAction))"
    Write-Host "  AC sleep after:       $(Format-ALGDurationSeconds -Seconds ([int]$Snapshot.AC.StandbyIdle))"
    Write-Host "  DC sleep after:       $(Format-ALGDurationSeconds -Seconds ([int]$Snapshot.DC.StandbyIdle))"
    Write-Host "  AC hibernate after:   $(Format-ALGDurationSeconds -Seconds ([int]$Snapshot.AC.HibernateIdle))"
    Write-Host "  DC hibernate after:   $(Format-ALGDurationSeconds -Seconds ([int]$Snapshot.DC.HibernateIdle))"
    Write-Host "  Poll seconds:         $($Config.PollSeconds)"
    Write-Host "  Process names:        $($Config.ProcessNames -join ', ')"

    if (@($Matches).Count -gt 0) {
        $matchText = @($Matches | ForEach-Object { Format-ALGProcessMatch -Process $_ }) -join ", "
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
    if ([bool]$State.Runtime.Protected -and $TaskState -ne "Running") {
        Write-Host "  Runtime warning:      protected state is present but task is not running; run start or stop to reconcile policy."
    }
    Write-Host "  Runtime power request: handle=$($State.Runtime.PowerRequest.HasHandle), system=$($State.Runtime.PowerRequest.SystemRequired), execution=$($State.Runtime.PowerRequest.ExecutionRequired)"
}

function Get-ALGSleepStates {
    $output = & powercfg /availablesleepstates 2>&1
    return @($output | Where-Object { $_ -ne "" })
}

function Get-ALGPowerRequestsText {
    try {
        $output = & powercfg /requests 2>&1
        return @($output | Where-Object { $_ -ne "" })
    }
    catch {
        return @("powercfg /requests unavailable in this shell: $($_.Exception.Message)")
    }
}

function Convert-ALGEventSummary {
    param($Event)

    $message = ($Event.Message -replace "\r?\n", " " -replace "\s+", " ").Trim()
    if ($message.Length -gt 180) {
        $message = $message.Substring(0, 180) + "..."
    }

    return [pscustomobject]@{
        TimeCreated = $Event.TimeCreated
        Id = $Event.Id
        Summary = $message
    }
}

function Get-ALGDiagnosticStartTime {
    param([int]$Hours)

    return (Get-Date).AddHours(-1 * [Math]::Max(1, $Hours))
}

function Get-ALGRecentPowerEvents {
    param([int]$Hours = 12)

    $start = Get-ALGDiagnosticStartTime -Hours $Hours
    $ids = 42, 107, 187, 506, 507, 566, 41, 172
    return @(Get-WinEvent -FilterHashtable @{LogName = "System"; StartTime = $start} -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -eq "Microsoft-Windows-Kernel-Power" -and $_.Id -in $ids } |
        Sort-Object TimeCreated -Descending |
        Select-Object -First 20 |
        ForEach-Object { Convert-ALGEventSummary -Event $_ })
}

function Get-ALGRecentWlanEvents {
    param([int]$Hours = 12)

    $start = Get-ALGDiagnosticStartTime -Hours $Hours
    return @(Get-WinEvent -FilterHashtable @{LogName = "Microsoft-Windows-WLAN-AutoConfig/Operational"; StartTime = $start} -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -in 8000, 8001, 8002, 8003, 11000, 11001, 11004, 11005 } |
        Sort-Object TimeCreated -Descending |
        Select-Object -First 20 |
        ForEach-Object { Convert-ALGEventSummary -Event $_ })
}

Export-ModuleMember -Function Write-ALGStatus, Get-ALGSleepStates, Get-ALGPowerRequestsText, Get-ALGRecentPowerEvents, Get-ALGRecentWlanEvents
