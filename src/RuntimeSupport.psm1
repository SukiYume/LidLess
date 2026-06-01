Set-StrictMode -Version 2.0

function Test-LLIsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-LLAdmin {
    param(
        [string]$ScriptPath,
        [string]$Command
    )

    if (Test-LLIsAdmin) {
        return
    }

    $psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" $Command"
    Start-Process -FilePath "powershell.exe" -ArgumentList $psArgs -Verb RunAs | Out-Null
    Write-Host "Administrator privileges are required. Relaunched elevated command: $Command"
    exit 0
}

function Write-LLLog {
    param(
        [string]$LogPath,
        [string]$Message
    )

    try {
        $dir = Split-Path -Parent $LogPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        if ((Test-Path $LogPath) -and ((Get-Item $LogPath).Length -gt 1MB)) {
            Clear-Content -Path $LogPath -ErrorAction SilentlyContinue
        }

        $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    }
    catch {
        $null = $_
        # Logging must not break power-policy cleanup.
    }
}

function Format-LLDurationSeconds {
    param([int]$Seconds)

    if ($Seconds -eq 0) {
        return "0 (Never)"
    }

    if ($Seconds -lt 60) {
        return "$Seconds sec"
    }

    $minutes = [Math]::Round($Seconds / 60, 2)
    return "$Seconds sec ($minutes min)"
}

function Format-LLProcessMatch {
    param($Process)

    return "$($Process.ProcessName)[$($Process.Id)]"
}

Export-ModuleMember -Function Test-LLIsAdmin, Ensure-LLAdmin, Write-LLLog, Format-LLDurationSeconds, Format-LLProcessMatch
