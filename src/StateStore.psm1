Set-StrictMode -Version 2.0

function New-LLPowerRequestState {
    return [pscustomobject]@{
        HasHandle = $false
        SystemRequired = $false
        ExecutionRequired = $false
    }
}

function New-LLRuntimeState {
    return [pscustomobject]@{
        Protected = $false
        PowerSource = "Unknown"
        Matches = @()
        Reason = "new state"
        LastHeartbeatAt = $null
        MonitorProcessId = $null
        PowerRequest = New-LLPowerRequestState
    }
}

function New-LLState {
    return [pscustomobject]@{
        Version = 2
        CreatedAt = (Get-Date).ToString("o")
        LastUpdatedAt = (Get-Date).ToString("o")
        Runtime = New-LLRuntimeState
        TouchedSchemes = @()
    }
}

function Add-LLPropertyIfMissing {
    param(
        $Object,
        [string]$Name,
        $Value
    )

    if (-not ($Object.PSObject.Properties.Name -contains $Name)) {
        Add-Member -InputObject $Object -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Repair-LLRuntimeShape {
    param($Runtime)

    $defaults = New-LLRuntimeState
    Add-LLPropertyIfMissing -Object $Runtime -Name "Protected" -Value $defaults.Protected
    Add-LLPropertyIfMissing -Object $Runtime -Name "PowerSource" -Value $defaults.PowerSource
    Add-LLPropertyIfMissing -Object $Runtime -Name "Matches" -Value $defaults.Matches
    Add-LLPropertyIfMissing -Object $Runtime -Name "Reason" -Value $defaults.Reason
    Add-LLPropertyIfMissing -Object $Runtime -Name "LastHeartbeatAt" -Value $defaults.LastHeartbeatAt
    Add-LLPropertyIfMissing -Object $Runtime -Name "MonitorProcessId" -Value $defaults.MonitorProcessId

    Add-LLPropertyIfMissing -Object $Runtime -Name "PowerRequest" -Value $null
    if ($null -eq $Runtime.PowerRequest) {
        $Runtime.PowerRequest = New-LLPowerRequestState
    }

    $powerRequestDefaults = New-LLPowerRequestState
    Add-LLPropertyIfMissing -Object $Runtime.PowerRequest -Name "HasHandle" -Value $powerRequestDefaults.HasHandle
    Add-LLPropertyIfMissing -Object $Runtime.PowerRequest -Name "SystemRequired" -Value $powerRequestDefaults.SystemRequired
    Add-LLPropertyIfMissing -Object $Runtime.PowerRequest -Name "ExecutionRequired" -Value $powerRequestDefaults.ExecutionRequired

    return $Runtime
}

function Repair-LLStateShape {
    param($State)

    $defaults = New-LLState
    Add-LLPropertyIfMissing -Object $State -Name "Version" -Value $defaults.Version
    Add-LLPropertyIfMissing -Object $State -Name "CreatedAt" -Value $defaults.CreatedAt
    Add-LLPropertyIfMissing -Object $State -Name "LastUpdatedAt" -Value $defaults.LastUpdatedAt
    Add-LLPropertyIfMissing -Object $State -Name "TouchedSchemes" -Value @()

    if (-not ($State.PSObject.Properties.Name -contains "Runtime") -or $null -eq $State.Runtime) {
        Add-LLPropertyIfMissing -Object $State -Name "Runtime" -Value (New-LLRuntimeState)
        $State.Runtime = New-LLRuntimeState
    }
    else {
        $State.Runtime = Repair-LLRuntimeShape -Runtime $State.Runtime
    }

    return $State
}

function Read-LLState {
    param([string]$StatePath)

    if (Test-Path $StatePath) {
        try {
            $state = Get-Content -Path $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            return Repair-LLStateShape -State $state
        }
        catch {
            return New-LLState
        }
    }

    return New-LLState
}

function Save-LLState {
    param(
        [string]$StatePath,
        $State
    )

    $dir = Split-Path -Parent $StatePath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $State.LastUpdatedAt = (Get-Date).ToString("o")
    $tmpPath = "$StatePath.tmp"
    $State | ConvertTo-Json -Depth 12 | Set-Content -Path $tmpPath -Encoding UTF8
    Move-Item -Path $tmpPath -Destination $StatePath -Force
}

function Remove-LLState {
    param([string]$StatePath)

    Remove-Item -Path $StatePath -Force -ErrorAction SilentlyContinue
}

function Set-LLStateRuntime {
    param(
        $State,
        [bool]$Protected,
        [string]$PowerSource,
        [string[]]$MatchText,
        [string]$Reason,
        $PowerRequestState
    )

    $State.Runtime = [pscustomobject]@{
        Protected = $Protected
        PowerSource = $PowerSource
        Matches = @($MatchText)
        Reason = $Reason
        LastHeartbeatAt = (Get-Date).ToString("o")
        MonitorProcessId = $PID
        PowerRequest = $PowerRequestState
    }
}

function Set-LLStatePowerRequest {
    param(
        $State,
        $PowerRequestState
    )

    $State.Runtime = Repair-LLRuntimeShape -Runtime $State.Runtime
    $State.Runtime.PowerRequest = $PowerRequestState
    $State.Runtime.LastHeartbeatAt = (Get-Date).ToString("o")
    $State.Runtime.MonitorProcessId = $PID
}

Export-ModuleMember -Function New-LLState, Read-LLState, Save-LLState, Remove-LLState, Set-LLStateRuntime, Set-LLStatePowerRequest
