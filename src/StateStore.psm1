Set-StrictMode -Version 2.0

function New-ALGPowerRequestState {
    return [pscustomobject]@{
        HasHandle = $false
        SystemRequired = $false
        ExecutionRequired = $false
    }
}

function New-ALGRuntimeState {
    return [pscustomobject]@{
        Protected = $false
        PowerSource = "Unknown"
        Matches = @()
        Reason = "new state"
        LastHeartbeatAt = $null
        MonitorProcessId = $null
        PowerRequest = New-ALGPowerRequestState
    }
}

function New-ALGState {
    return [pscustomobject]@{
        Version = 2
        CreatedAt = (Get-Date).ToString("o")
        LastUpdatedAt = (Get-Date).ToString("o")
        Runtime = New-ALGRuntimeState
        TouchedSchemes = @()
    }
}

function Add-ALGPropertyIfMissing {
    param(
        $Object,
        [string]$Name,
        $Value
    )

    if (-not ($Object.PSObject.Properties.Name -contains $Name)) {
        Add-Member -InputObject $Object -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Repair-ALGRuntimeShape {
    param($Runtime)

    $defaults = New-ALGRuntimeState
    Add-ALGPropertyIfMissing -Object $Runtime -Name "Protected" -Value $defaults.Protected
    Add-ALGPropertyIfMissing -Object $Runtime -Name "PowerSource" -Value $defaults.PowerSource
    Add-ALGPropertyIfMissing -Object $Runtime -Name "Matches" -Value $defaults.Matches
    Add-ALGPropertyIfMissing -Object $Runtime -Name "Reason" -Value $defaults.Reason
    Add-ALGPropertyIfMissing -Object $Runtime -Name "LastHeartbeatAt" -Value $defaults.LastHeartbeatAt
    Add-ALGPropertyIfMissing -Object $Runtime -Name "MonitorProcessId" -Value $defaults.MonitorProcessId

    Add-ALGPropertyIfMissing -Object $Runtime -Name "PowerRequest" -Value $null
    if ($null -eq $Runtime.PowerRequest) {
        $Runtime.PowerRequest = New-ALGPowerRequestState
    }

    $powerRequestDefaults = New-ALGPowerRequestState
    Add-ALGPropertyIfMissing -Object $Runtime.PowerRequest -Name "HasHandle" -Value $powerRequestDefaults.HasHandle
    Add-ALGPropertyIfMissing -Object $Runtime.PowerRequest -Name "SystemRequired" -Value $powerRequestDefaults.SystemRequired
    Add-ALGPropertyIfMissing -Object $Runtime.PowerRequest -Name "ExecutionRequired" -Value $powerRequestDefaults.ExecutionRequired

    return $Runtime
}

function Repair-ALGStateShape {
    param($State)

    $defaults = New-ALGState
    Add-ALGPropertyIfMissing -Object $State -Name "Version" -Value $defaults.Version
    Add-ALGPropertyIfMissing -Object $State -Name "CreatedAt" -Value $defaults.CreatedAt
    Add-ALGPropertyIfMissing -Object $State -Name "LastUpdatedAt" -Value $defaults.LastUpdatedAt
    Add-ALGPropertyIfMissing -Object $State -Name "TouchedSchemes" -Value @()

    if (-not ($State.PSObject.Properties.Name -contains "Runtime") -or $null -eq $State.Runtime) {
        Add-ALGPropertyIfMissing -Object $State -Name "Runtime" -Value (New-ALGRuntimeState)
        $State.Runtime = New-ALGRuntimeState
    }
    else {
        $State.Runtime = Repair-ALGRuntimeShape -Runtime $State.Runtime
    }

    return $State
}

function Read-ALGState {
    param([string]$StatePath)

    if (Test-Path $StatePath) {
        try {
            $state = Get-Content -Path $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            return Repair-ALGStateShape -State $state
        }
        catch {
            return New-ALGState
        }
    }

    return New-ALGState
}

function Save-ALGState {
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

function Remove-ALGState {
    param([string]$StatePath)

    Remove-Item -Path $StatePath -Force -ErrorAction SilentlyContinue
}

function Set-ALGStateRuntime {
    param(
        $State,
        [bool]$Protected,
        [string]$PowerSource,
        [string[]]$Matches,
        [string]$Reason,
        $PowerRequestState
    )

    $State.Runtime = [pscustomobject]@{
        Protected = $Protected
        PowerSource = $PowerSource
        Matches = @($Matches)
        Reason = $Reason
        LastHeartbeatAt = (Get-Date).ToString("o")
        MonitorProcessId = $PID
        PowerRequest = $PowerRequestState
    }
}

function Set-ALGStatePowerRequest {
    param(
        $State,
        $PowerRequestState
    )

    $State.Runtime = Repair-ALGRuntimeShape -Runtime $State.Runtime
    $State.Runtime.PowerRequest = $PowerRequestState
    $State.Runtime.LastHeartbeatAt = (Get-Date).ToString("o")
    $State.Runtime.MonitorProcessId = $PID
}

Export-ModuleMember -Function New-ALGState, Read-ALGState, Save-ALGState, Remove-ALGState, Set-ALGStateRuntime, Set-ALGStatePowerRequest
