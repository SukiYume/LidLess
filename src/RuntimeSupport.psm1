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

    $psArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass")
    if ($Command -eq "once") {
        $psArgs += "-NoExit"
    }
    $psArgs += @("-File", "`"$ScriptPath`"", $Command)
    $waitForChild = Test-LLWaitForElevatedCommand -Command $Command
    $startArgs = @{
        FilePath = "powershell.exe"
        ArgumentList = $psArgs
        Verb = "RunAs"
        PassThru = $true
        ErrorAction = "Stop"
    }
    if ($waitForChild) {
        $startArgs.Wait = $true
    }

    Write-Host "Administrator privileges are required. Requesting elevation for: $Command"
    try {
        $process = Start-Process @startArgs
    }
    catch {
        Write-Host "Administrator elevation was cancelled or failed: $($_.Exception.Message)"
        exit 1
    }

    if ($waitForChild) {
        exit $process.ExitCode
    }

    exit 0
}

function Test-LLWaitForElevatedCommand {
    param([string]$Command)

    return ($Command -notin @("run", "once"))
}

function Test-LLFileSystemRightsIncludeWrite {
    param([Security.AccessControl.FileSystemRights]$Rights)

    # Use atomic write/control bits only. Composite values such as Write, Modify,
    # and FullControl overlap with read/execute flags and can make a read-only
    # ACL entry look writable.
    $writeRights =
        [Security.AccessControl.FileSystemRights]::WriteData -bor
        [Security.AccessControl.FileSystemRights]::AppendData -bor
        [Security.AccessControl.FileSystemRights]::CreateFiles -bor
        [Security.AccessControl.FileSystemRights]::CreateDirectories -bor
        [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
        [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership -bor
        [Security.AccessControl.FileSystemRights]::Delete

    return (($Rights -band $writeRights) -ne 0)
}

function Get-LLIdentitySidText {
    param($IdentityReference)

    try {
        return $IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
    }
    catch {
        return [string]$IdentityReference
    }
}

function Test-LLUnsafeInstallWriter {
    param($IdentityReference)

    $sidText = Get-LLIdentitySidText -IdentityReference $IdentityReference
    if ($sidText -match "^S-1-5-21-.+-500$") {
        return $false
    }

    $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $unsafeSids = @(
        "S-1-1-0",
        "S-1-5-11",
        "S-1-5-32-545",
        $currentUserSid
    )

    if ($unsafeSids -contains $sidText) {
        return $true
    }

    return ($sidText -match "^S-1-5-21-.+-\d+$")
}

function Get-LLUnsafeInstallPathAccess {
    param([string]$ScriptRoot)

    $paths = @(
        $ScriptRoot,
        (Join-Path $ScriptRoot "LidLess.ps1"),
        (Join-Path $ScriptRoot "src")
    )
    $srcRoot = Join-Path $ScriptRoot "src"
    if (Test-Path $srcRoot) {
        $paths += @(Get-ChildItem -Path $srcRoot -Filter "*.psm1" -File | ForEach-Object { $_.FullName })
    }

    $findings = @()
    foreach ($path in @($paths | Where-Object { Test-Path $_ } | Select-Object -Unique)) {
        $acl = Get-Acl -Path $path
        # Conservative ACL screen: an explicit deny may produce a false positive,
        # but ambiguous SYSTEM task install paths should fail closed.
        foreach ($rule in @($acl.Access)) {
            if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) {
                continue
            }
            if (-not (Test-LLFileSystemRightsIncludeWrite -Rights $rule.FileSystemRights)) {
                continue
            }
            if (-not (Test-LLUnsafeInstallWriter -IdentityReference $rule.IdentityReference)) {
                continue
            }

            $findings += [pscustomobject]@{
                Path = $path
                Identity = [string]$rule.IdentityReference
                Rights = [string]$rule.FileSystemRights
            }
        }
    }

    return @($findings)
}

function Assert-LLTrustedInstallPath {
    param([string]$ScriptRoot)

    $unsafeAccess = @(Get-LLUnsafeInstallPathAccess -ScriptRoot $ScriptRoot)
    if ($unsafeAccess.Count -eq 0) {
        return
    }

    $examples = @($unsafeAccess | Select-Object -First 5 | ForEach-Object {
        "  $($_.Identity) can write $($_.Path) ($($_.Rights))"
    })

    throw @"
LidLess refuses to register a SYSTEM scheduled task from a user-writable folder:
  $ScriptRoot

Move LidLess to an administrator-writable install directory such as:
  $env:ProgramFiles\LidLess

Unsafe write access detected:
$($examples -join [Environment]::NewLine)
"@
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
            $archivePath = "$LogPath.1"
            Remove-Item -Path $archivePath -Force -ErrorAction SilentlyContinue
            Move-Item -Path $LogPath -Destination $archivePath -Force -ErrorAction SilentlyContinue
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

function Get-LLObjectPropertyValue {
    param(
        $Object,
        [string[]]$Names
    )

    if ($null -eq $Object) {
        return $null
    }

    foreach ($name in $Names) {
        $property = $Object.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value) {
            return $property.Value
        }
    }

    return $null
}

function Format-LLProcessMatch {
    param($Process)

    $name = Get-LLObjectPropertyValue -Object $Process -Names @("ProcessName", "Name")
    $id = Get-LLObjectPropertyValue -Object $Process -Names @("Id", "ProcessId")

    if ([string]::IsNullOrWhiteSpace([string]$name)) {
        $name = "unknown-process"
    }
    if ([string]::IsNullOrWhiteSpace([string]$id)) {
        $id = "unknown-id"
    }

    return "$name[$id]"
}

Export-ModuleMember -Function Test-LLIsAdmin, Ensure-LLAdmin, Assert-LLTrustedInstallPath, Write-LLLog, Format-LLDurationSeconds, Format-LLProcessMatch
