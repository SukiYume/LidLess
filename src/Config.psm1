Set-StrictMode -Version 2.0

function New-ALGDefaultSourceConfig {
    param([bool]$Enabled)

    return [pscustomobject]@{
        Enabled = $Enabled
        LidCloseDoNothing = $true
        PreventIdleSleep = $true
        PreventHibernate = $true
        HoldSystemRequiredRequest = $true
        HoldExecutionRequiredRequest = $true
    }
}

function New-ALGDefaultConfig {
    return [pscustomobject]@{
        ProcessNames = @("claude", "codex", "Codex Desktop")
        PollSeconds = 5
        AC = New-ALGDefaultSourceConfig -Enabled $true
        DC = New-ALGDefaultSourceConfig -Enabled $false
        Diagnostics = [pscustomobject]@{
            IncludeRecentPowerEvents = $true
            EventLookbackHours = 12
        }
    }
}

function Get-ALGJsonProperty {
    param(
        $Object,
        [string]$Name,
        $DefaultValue
    )

    if ($null -ne $Object -and ($Object.PSObject.Properties.Name -contains $Name)) {
        return $Object.$Name
    }

    return $DefaultValue
}

function Normalize-ALGProcessName {
    param([string]$Name)

    $value = $Name.Trim()
    if ($value.EndsWith(".exe", [StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring(0, $value.Length - 4)
    }

    return $value
}

function Convert-ALGSourceConfig {
    param(
        $Raw,
        [bool]$DefaultEnabled
    )

    $defaults = New-ALGDefaultSourceConfig -Enabled $DefaultEnabled
    if ($null -eq $Raw) {
        return $defaults
    }

    return [pscustomobject]@{
        Enabled = [bool](Get-ALGJsonProperty -Object $Raw -Name "enabled" -DefaultValue $defaults.Enabled)
        LidCloseDoNothing = [bool](Get-ALGJsonProperty -Object $Raw -Name "lidCloseDoNothing" -DefaultValue $defaults.LidCloseDoNothing)
        PreventIdleSleep = [bool](Get-ALGJsonProperty -Object $Raw -Name "preventIdleSleep" -DefaultValue $defaults.PreventIdleSleep)
        PreventHibernate = [bool](Get-ALGJsonProperty -Object $Raw -Name "preventHibernate" -DefaultValue $defaults.PreventHibernate)
        HoldSystemRequiredRequest = [bool](Get-ALGJsonProperty -Object $Raw -Name "holdSystemRequiredRequest" -DefaultValue $defaults.HoldSystemRequiredRequest)
        HoldExecutionRequiredRequest = [bool](Get-ALGJsonProperty -Object $Raw -Name "holdExecutionRequiredRequest" -DefaultValue $defaults.HoldExecutionRequiredRequest)
    }
}

function Get-ALGConfig {
    param([string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) {
        New-ALGDefaultConfig | ConvertTo-Json -Depth 8 | Set-Content -Path $ConfigPath -Encoding UTF8
    }

    $raw = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $defaults = New-ALGDefaultConfig

    $rawNames = Get-ALGJsonProperty -Object $raw -Name "processNames" -DefaultValue $defaults.ProcessNames
    $names = @()
    $seenNames = @{}
    foreach ($name in @($rawNames)) {
        if ($null -ne $name) {
            $normalized = Normalize-ALGProcessName -Name ([string]$name)
            $nameKey = $normalized.ToLowerInvariant()
            if ($normalized.Length -gt 0 -and -not $seenNames.ContainsKey($nameKey)) {
                $names += $normalized
                $seenNames[$nameKey] = $true
            }
        }
    }

    if ($names.Count -eq 0) {
        throw "config.json must contain at least one process name."
    }

    $pollSeconds = [Math]::Max(2, [int](Get-ALGJsonProperty -Object $raw -Name "pollSeconds" -DefaultValue $defaults.PollSeconds))

    $oldApplyOnAC = Get-ALGJsonProperty -Object $raw -Name "applyOnAC" -DefaultValue $null
    $oldApplyOnDC = Get-ALGJsonProperty -Object $raw -Name "applyOnDC" -DefaultValue $null

    $acDefaultEnabled = if ($null -ne $oldApplyOnAC) { [bool]$oldApplyOnAC } else { $true }
    $dcDefaultEnabled = if ($null -ne $oldApplyOnDC) { [bool]$oldApplyOnDC } else { $false }

    $ac = Convert-ALGSourceConfig -Raw (Get-ALGJsonProperty -Object $raw -Name "ac" -DefaultValue $null) -DefaultEnabled $acDefaultEnabled
    $dc = Convert-ALGSourceConfig -Raw (Get-ALGJsonProperty -Object $raw -Name "dc" -DefaultValue $null) -DefaultEnabled $dcDefaultEnabled

    $rawDiagnostics = Get-ALGJsonProperty -Object $raw -Name "diagnostics" -DefaultValue $null
    $diagnostics = [pscustomobject]@{
        IncludeRecentPowerEvents = [bool](Get-ALGJsonProperty -Object $rawDiagnostics -Name "includeRecentPowerEvents" -DefaultValue $defaults.Diagnostics.IncludeRecentPowerEvents)
        EventLookbackHours = [int](Get-ALGJsonProperty -Object $rawDiagnostics -Name "eventLookbackHours" -DefaultValue $defaults.Diagnostics.EventLookbackHours)
    }

    if (-not $ac.Enabled -and -not $dc.Enabled) {
        throw "At least one source must be enabled: ac.enabled or dc.enabled."
    }

    return [pscustomobject]@{
        ProcessNames = @($names)
        PollSeconds = $pollSeconds
        AC = $ac
        DC = $dc
        Diagnostics = $diagnostics
    }
}

function Get-ALGSourceConfig {
    param(
        $Config,
        [ValidateSet("AC", "DC")]
        [string]$PowerSource
    )

    if ($PowerSource -eq "AC") {
        return $Config.AC
    }

    return $Config.DC
}

Export-ModuleMember -Function New-ALGDefaultConfig, Get-ALGConfig, Get-ALGSourceConfig
