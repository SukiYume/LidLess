Set-StrictMode -Version 2.0

function Test-LLAccessDeniedText {
    param([string]$Text)

    return ($Text -match 'Access is denied|Access denied|\u62d2\u7edd\u8bbf\u95ee|\u5b58\u53d6\u88ab\u62d2')
}

function Test-LLTaskNotFoundText {
    param([string]$Text)

    return ($Text -match 'cannot find|not exist|No .* found|\u627e\u4e0d\u5230|\u4e0d\u5b58\u5728')
}

function Get-LLTaskState {
    param([string]$TaskName)

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        if ($task) {
            return [string]$task.State
        }
    }
    catch {
        $message = $_.Exception.Message
        if (Test-LLAccessDeniedText -Text $message) {
            return "Access denied"
        }
    }

    $exitCode = 0
    try {
        $output = & schtasks.exe /Query /TN $TaskName /FO LIST 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        $output = @($_.Exception.Message)
        $exitCode = 1
    }

    if ($exitCode -ne 0) {
        $text = ($output | ForEach-Object { $_.ToString() } | Out-String)
        if (Test-LLAccessDeniedText -Text $text) {
            return "Access denied"
        }
        if (Test-LLTaskNotFoundText -Text $text) {
            return "Not installed"
        }

        return "Unavailable"
    }

    return "Not installed"
}

function Register-LLTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath
    )

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" run"

    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Days 365) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1)

    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "LidLess keeps configured agent processes awake and network-reachable." `
        -Force | Out-Null
}

function Start-LLTask {
    param([string]$TaskName)

    Start-ScheduledTask -TaskName $TaskName
}

function Stop-LLTask {
    param([string]$TaskName)

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        return
    }

    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 250
        $state = Get-LLTaskState -TaskName $TaskName
        if ($state -ne "Running") {
            return
        }
    }
}

function Unregister-LLTask {
    param([string]$TaskName)

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function Get-LLTaskState, Register-LLTask, Start-LLTask, Stop-LLTask, Unregister-LLTask
