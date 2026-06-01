Set-StrictMode -Version 2.0

function Get-ALGMatchingProcesses {
    param([string[]]$ProcessNames)

    $processMatches = @()
    foreach ($name in $ProcessNames) {
        try {
            $processMatches += @(Get-Process -Name $name -ErrorAction SilentlyContinue)
        }
        catch {
            # Keep monitoring even if one wildcard or process query fails.
        }
    }

    return @($processMatches | Sort-Object -Property Id -Unique)
}

Export-ModuleMember -Function Get-ALGMatchingProcesses
