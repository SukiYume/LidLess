Set-StrictMode -Version 2.0

$script:PowerCfgTimeoutMilliseconds = 15000

$script:PowerSettings = [ordered]@{
    LidAction = @{
        Label = "Lid close action"
        Subgroup = "4f971e89-eebd-4455-a8de-9e59040e7347"
        Setting = "5ca83367-6e45-459f-a27b-476b1d01c936"
        ProtectedValue = 0
    }
    StandbyIdle = @{
        Label = "Sleep after"
        Subgroup = "238c9fa8-0aad-41ed-83f4-97be242c8f20"
        Setting = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da"
        ProtectedValue = 0
    }
    HibernateIdle = @{
        Label = "Hibernate after"
        Subgroup = "238c9fa8-0aad-41ed-83f4-97be242c8f20"
        Setting = "9d7815a6-7ee4-497e-8888-515a05f02364"
        ProtectedValue = 0
    }
}

function Get-ALGPowerSettingKeys {
    return @($script:PowerSettings.Keys)
}

function Join-ALGProcessArguments {
    param([string[]]$Arguments)

    return ($Arguments | ForEach-Object {
        $value = [string]$_
        if ($value -match '[\s"]') {
            '"' + ($value -replace '"', '\"') + '"'
        }
        else {
            $value
        }
    }) -join " "
}

function Invoke-ALGPowerCfg {
    param([string[]]$Arguments)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = "powercfg.exe"
    $process.StartInfo.Arguments = Join-ALGProcessArguments -Arguments $Arguments
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.CreateNoWindow = $true

    [void]$process.Start()
    if (-not $process.WaitForExit($script:PowerCfgTimeoutMilliseconds)) {
        try {
            $process.Kill()
        }
        catch {
            # The process may have exited between WaitForExit and Kill.
        }
        throw "powercfg $($Arguments -join ' ') timed out after $script:PowerCfgTimeoutMilliseconds ms."
    }

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $output = @()
    if ($stdout.Length -gt 0) {
        $output += @($stdout -split "\r?\n" | Where-Object { $_ -ne "" })
    }
    if ($stderr.Length -gt 0) {
        $output += @($stderr -split "\r?\n" | Where-Object { $_ -ne "" })
    }

    if ($process.ExitCode -ne 0) {
        throw "powercfg $($Arguments -join ' ') failed: $($output -join ' ')"
    }

    return $output
}

function Get-ALGActivePowerSchemeGuid {
    $output = Invoke-ALGPowerCfg -Arguments @("/getactivescheme")
    $text = ($output | Out-String)
    if ($text -match "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") {
        return $Matches[1].ToLowerInvariant()
    }

    throw "Could not read active power scheme GUID."
}

function Get-ALGPowerSettingRegPath {
    param(
        [string]$SchemeGuid,
        [ValidateSet("LidAction", "StandbyIdle", "HibernateIdle")]
        [string]$SettingKey
    )

    $definition = $script:PowerSettings[$SettingKey]
    return "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$SchemeGuid\$($definition.Subgroup)\$($definition.Setting)"
}

function Get-ALGPowerSettingValue {
    param(
        [string]$SchemeGuid,
        [ValidateSet("AC", "DC")]
        [string]$PowerSource,
        [ValidateSet("LidAction", "StandbyIdle", "HibernateIdle")]
        [string]$SettingKey
    )

    $regPath = Get-ALGPowerSettingRegPath -SchemeGuid $SchemeGuid -SettingKey $SettingKey
    $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
    if ($null -ne $props -and $PowerSource -eq "AC" -and ($props.PSObject.Properties.Name -contains "ACSettingIndex")) {
        return [int]$props.ACSettingIndex
    }
    if ($null -ne $props -and $PowerSource -eq "DC" -and ($props.PSObject.Properties.Name -contains "DCSettingIndex")) {
        return [int]$props.DCSettingIndex
    }

    return Get-ALGPowerSettingValueFromPowerCfg -SchemeGuid $SchemeGuid -PowerSource $PowerSource -SettingKey $SettingKey
}

function Get-ALGPowerSettingValueFromPowerCfg {
    param(
        [string]$SchemeGuid,
        [ValidateSet("AC", "DC")]
        [string]$PowerSource,
        [ValidateSet("LidAction", "StandbyIdle", "HibernateIdle")]
        [string]$SettingKey
    )

    $definition = $script:PowerSettings[$SettingKey]
    $output = @(Invoke-ALGPowerCfg -Arguments @("/query", $SchemeGuid, $definition.Subgroup, $definition.Setting))
    $sourceLabels = @()
    if ($PowerSource -eq "AC") {
        $sourceLabels = @("Current AC Power Setting Index")
    }
    else {
        $sourceLabels = @("Current DC Power Setting Index")
    }

    foreach ($line in $output) {
        $lineText = [string]$line
        foreach ($label in $sourceLabels) {
            if ($lineText.IndexOf($label, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and $lineText -match "0x([0-9a-fA-F]+)") {
                return [Convert]::ToInt32($Matches[1], 16)
            }
        }
    }

    # Locale fallback: powercfg lists current AC and DC indexes last in known
    # Windows builds, even when labels are localized differently.
    $hexValues = @()
    foreach ($line in $output) {
        $lineText = [string]$line
        if ($lineText -match "0x([0-9a-fA-F]+)") {
            $hexValues += $Matches[1]
        }
    }

    if ($hexValues.Count -ge 2) {
        $index = if ($PowerSource -eq "AC") { $hexValues.Count - 2 } else { $hexValues.Count - 1 }
        return [Convert]::ToInt32($hexValues[$index], 16)
    }

    throw "Could not read $PowerSource $SettingKey for scheme $SchemeGuid from registry or powercfg."
}

function Set-ALGPowerSettingValue {
    param(
        [string]$SchemeGuid,
        [ValidateSet("AC", "DC")]
        [string]$PowerSource,
        [ValidateSet("LidAction", "StandbyIdle", "HibernateIdle")]
        [string]$SettingKey,
        [int]$Value
    )

    $definition = $script:PowerSettings[$SettingKey]
    if ($PowerSource -eq "AC") {
        Invoke-ALGPowerCfg -Arguments @("/setacvalueindex", $SchemeGuid, $definition.Subgroup, $definition.Setting, [string]$Value) | Out-Null
    }
    else {
        Invoke-ALGPowerCfg -Arguments @("/setdcvalueindex", $SchemeGuid, $definition.Subgroup, $definition.Setting, [string]$Value) | Out-Null
    }

    $active = Get-ALGActivePowerSchemeGuid
    if ($active -ieq $SchemeGuid) {
        Invoke-ALGPowerCfg -Arguments @("/setactive", $SchemeGuid) | Out-Null
    }
}

function Get-ALGPowerPolicySnapshotForSource {
    param(
        [string]$SchemeGuid,
        [ValidateSet("AC", "DC")]
        [string]$PowerSource
    )

    $values = [ordered]@{}
    foreach ($settingKey in (Get-ALGPowerSettingKeys)) {
        $values[$settingKey] = Get-ALGPowerSettingValue -SchemeGuid $SchemeGuid -PowerSource $PowerSource -SettingKey $settingKey
    }

    return [pscustomobject]$values
}

function Get-ALGPowerPolicySnapshot {
    param([string]$SchemeGuid)

    return [pscustomobject]@{
        AC = Get-ALGPowerPolicySnapshotForSource -SchemeGuid $SchemeGuid -PowerSource "AC"
        DC = Get-ALGPowerPolicySnapshotForSource -SchemeGuid $SchemeGuid -PowerSource "DC"
    }
}

function New-ALGSchemeStateEntry {
    param([string]$SchemeGuid)

    $snapshot = Get-ALGPowerPolicySnapshot -SchemeGuid $SchemeGuid
    $entry = [ordered]@{
        SchemeGuid = $SchemeGuid
    }

    foreach ($source in @("AC", "DC")) {
        $sourceSnapshot = $snapshot.PSObject.Properties[$source].Value
        foreach ($settingKey in (Get-ALGPowerSettingKeys)) {
            $entry["Original$settingKey$source"] = [int]$sourceSnapshot.PSObject.Properties[$settingKey].Value
            $entry["Owned$settingKey$source"] = $false
        }
    }

    return [pscustomobject]$entry
}

function Find-ALGSchemeStateEntry {
    param(
        $State,
        [string]$SchemeGuid
    )

    foreach ($entry in @($State.TouchedSchemes)) {
        if ($entry.SchemeGuid -ieq $SchemeGuid) {
            return $entry
        }
    }

    return $null
}

function Ensure-ALGSchemeStateEntry {
    param(
        $State,
        [string]$SchemeGuid
    )

    $entry = Find-ALGSchemeStateEntry -State $State -SchemeGuid $SchemeGuid
    if ($null -ne $entry) {
        $snapshot = $null
        foreach ($source in @("AC", "DC")) {
            foreach ($settingKey in (Get-ALGPowerSettingKeys)) {
                $props = Get-ALGStatePropertyNames -PowerSource $source -SettingKey $settingKey
                if (-not ($entry.PSObject.Properties.Name -contains $props.Original)) {
                    if ($null -eq $snapshot) {
                        $snapshot = Get-ALGPowerPolicySnapshot -SchemeGuid $SchemeGuid
                    }
                    $sourceSnapshot = $snapshot.PSObject.Properties[$source].Value
                    Add-Member -InputObject $entry -NotePropertyName $props.Original -NotePropertyValue ([int]$sourceSnapshot.PSObject.Properties[$settingKey].Value)
                }
                if (-not ($entry.PSObject.Properties.Name -contains $props.Owned)) {
                    Add-Member -InputObject $entry -NotePropertyName $props.Owned -NotePropertyValue $false
                }
            }
        }
        return $entry
    }

    $entry = New-ALGSchemeStateEntry -SchemeGuid $SchemeGuid
    $State.TouchedSchemes = @(@($State.TouchedSchemes) + $entry)
    return $entry
}

function Get-ALGEnabledSettingKeysForSource {
    param($SourceConfig)

    $enabledBySetting = @{
        LidAction = [bool]$SourceConfig.LidCloseDoNothing
        StandbyIdle = [bool]$SourceConfig.PreventIdleSleep
        HibernateIdle = [bool]$SourceConfig.PreventHibernate
    }

    $keys = @()
    foreach ($settingKey in (Get-ALGPowerSettingKeys)) {
        if ([bool]$enabledBySetting[$settingKey]) {
            $keys += $settingKey
        }
    }

    return $keys
}

function Get-ALGStatePropertyNames {
    param(
        [ValidateSet("AC", "DC")]
        [string]$PowerSource,
        [ValidateSet("LidAction", "StandbyIdle", "HibernateIdle")]
        [string]$SettingKey
    )

    return [pscustomobject]@{
        Owned = "Owned$SettingKey$PowerSource"
        Original = "Original$SettingKey$PowerSource"
    }
}

function Enable-ALGPolicyProtection {
    param(
        $State,
        $Config,
        [string]$SchemeGuid,
        [string]$LogPath
    )

    $entry = Ensure-ALGSchemeStateEntry -State $State -SchemeGuid $SchemeGuid
    $changed = $false

    foreach ($source in @("AC", "DC")) {
        $sourceConfig = Get-ALGSourceConfig -Config $Config -PowerSource $source
        if (-not [bool]$sourceConfig.Enabled) {
            continue
        }

        foreach ($settingKey in (Get-ALGEnabledSettingKeysForSource -SourceConfig $sourceConfig)) {
            $definition = $script:PowerSettings[$settingKey]
            $protectedValue = [int]$definition.ProtectedValue
            $current = Get-ALGPowerSettingValue -SchemeGuid $SchemeGuid -PowerSource $source -SettingKey $settingKey
            $props = Get-ALGStatePropertyNames -PowerSource $source -SettingKey $settingKey

            if ($current -ne $protectedValue) {
                if (-not [bool]$entry.($props.Owned)) {
                    $entry.($props.Original) = [int]$current
                }
                Set-ALGPowerSettingValue -SchemeGuid $SchemeGuid -PowerSource $source -SettingKey $settingKey -Value $protectedValue
                $entry.($props.Owned) = $true
                $changed = $true
                if ($LogPath -and (Get-Command Write-ALGLog -ErrorAction SilentlyContinue)) {
                    Write-ALGLog -LogPath $LogPath -Message "Set $($definition.Label) $source to $protectedValue for scheme $SchemeGuid."
                }
            }
        }
    }

    return $changed
}

function Restore-ALGPolicyProtection {
    param($State)

    $changed = $false
    foreach ($entry in @($State.TouchedSchemes)) {
        if (-not $entry.SchemeGuid) {
            continue
        }

        $schemeGuid = [string]$entry.SchemeGuid
        foreach ($source in @("AC", "DC")) {
            foreach ($settingKey in (Get-ALGPowerSettingKeys)) {
                $definition = $script:PowerSettings[$settingKey]
                $protectedValue = [int]$definition.ProtectedValue
                $props = Get-ALGStatePropertyNames -PowerSource $source -SettingKey $settingKey

                if (-not ($entry.PSObject.Properties.Name -contains $props.Owned)) {
                    continue
                }

                if (-not [bool]$entry.($props.Owned)) {
                    continue
                }

                $current = Get-ALGPowerSettingValue -SchemeGuid $schemeGuid -PowerSource $source -SettingKey $settingKey
                if ($current -eq $protectedValue) {
                    $original = [int]$entry.($props.Original)
                    Set-ALGPowerSettingValue -SchemeGuid $schemeGuid -PowerSource $source -SettingKey $settingKey -Value $original
                    $changed = $true
                }

                $entry.($props.Owned) = $false
            }
        }
    }

    return $changed
}

Export-ModuleMember -Function Get-ALGActivePowerSchemeGuid, Get-ALGPowerPolicySnapshot, Enable-ALGPolicyProtection, Restore-ALGPolicyProtection, Get-ALGPowerSettingValue
