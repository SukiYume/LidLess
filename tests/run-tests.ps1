Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

Import-Module (Join-Path $RepoRoot "src\RuntimeSupport.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $RepoRoot "src\Config.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $RepoRoot "src\StateStore.psm1") -Force -DisableNameChecking

$script:Passed = 0

function Assert-ALGTrue {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-ALGEqual {
    param(
        $Expected,
        $Actual,
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Invoke-ALGTest {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    & $Body
    $script:Passed++
    Write-Host "[pass] $Name"
}

Invoke-ALGTest "PowerShell files parse" {
    $allErrors = @()
    Get-ChildItem -Path $RepoRoot -Recurse -Include *.ps1, *.psm1 | ForEach-Object {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors) {
            $allErrors += $parseErrors | ForEach-Object { "$($_.Extent.File):$($_.Extent.StartLineNumber): $($_.Message)" }
        }
    }

    Assert-ALGEqual 0 $allErrors.Count ($allErrors -join [Environment]::NewLine)
}

Invoke-ALGTest "Default config focuses on task-like agent processes" {
    $config = New-ALGDefaultConfig
    Assert-ALGEqual "claude,codex,Codex Desktop" ($config.ProcessNames -join ",") "Unexpected default process names."
}

Invoke-ALGTest "Config normalizes exe suffix and de-duplicates case-insensitively" {
    $tempDir = Join-Path $env:TEMP ("alg-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        $configPath = Join-Path $tempDir "config.json"
        @"
{
  "processNames": ["codex.exe", "Codex", " claude "],
  "pollSeconds": 1,
  "ac": { "enabled": true },
  "dc": { "enabled": false }
}
"@ | Set-Content -Path $configPath -Encoding UTF8

        $config = Get-ALGConfig -ConfigPath $configPath
        Assert-ALGEqual "codex,claude" ($config.ProcessNames -join ",") "Process names were not normalized."
        Assert-ALGEqual 2 $config.PollSeconds "PollSeconds should be clamped to minimum."
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-ALGTest "Legacy state with missing PowerRequest is repaired" {
    $tempDir = Join-Path $env:TEMP ("alg-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        $statePath = Join-Path $tempDir "state.json"
        @"
{
  "Runtime": {
    "Protected": true,
    "PowerSource": "AC",
    "Matches": [],
    "Reason": "legacy"
  },
  "TouchedSchemes": []
}
"@ | Set-Content -Path $statePath -Encoding UTF8

        $state = Read-ALGState -StatePath $statePath
        Assert-ALGTrue ($state.Runtime.PSObject.Properties.Name -contains "PowerRequest") "PowerRequest was not added."
        Assert-ALGTrue ($state.Runtime.PowerRequest.PSObject.Properties.Name -contains "HasHandle") "HasHandle was not added."
        Assert-ALGTrue ($state.Runtime.PSObject.Properties.Name -contains "LastHeartbeatAt") "LastHeartbeatAt was not added."
        Assert-ALGTrue ($state.Runtime.PSObject.Properties.Name -contains "MonitorProcessId") "MonitorProcessId was not added."
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-ALGTest "Process match formatting is shared" {
    $process = [pscustomobject]@{
        ProcessName = "codex"
        Id = 1234
    }

    Assert-ALGEqual "codex[1234]" (Format-ALGProcessMatch -Process $process) "Unexpected match text."
}

Write-Host "All tests passed ($script:Passed)."
