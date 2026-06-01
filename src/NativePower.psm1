Set-StrictMode -Version 2.0

$script:PowerRequestHandle = [IntPtr]::Zero
$script:SystemRequestSet = $false
$script:ExecutionRequestSet = $false

function Ensure-LLNativePowerTypes {
    if (([System.Management.Automation.PSTypeName]"LidLess.NativePower").Type) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace LidLess {
    [StructLayout(LayoutKind.Sequential)]
    public struct SYSTEM_POWER_STATUS {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte Reserved1;
        public int BatteryLifeTime;
        public int BatteryFullLifeTime;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct REASON_CONTEXT {
        public uint Version;
        public uint Flags;
        public IntPtr SimpleReasonString;
    }

    public static class NativePower {
        public const uint POWER_REQUEST_CONTEXT_VERSION = 0;
        public const uint POWER_REQUEST_CONTEXT_SIMPLE_STRING = 0x1;
        public const int PowerRequestSystemRequired = 1;
        public const int PowerRequestExecutionRequired = 3;
        public const uint ES_CONTINUOUS = 0x80000000;
        public const uint ES_SYSTEM_REQUIRED = 0x00000001;

        [DllImport("kernel32.dll")]
        public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS status);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr PowerCreateRequest(ref REASON_CONTEXT context);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool PowerSetRequest(IntPtr powerRequestHandle, int requestType);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool PowerClearRequest(IntPtr powerRequestHandle, int requestType);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern uint SetThreadExecutionState(uint flags);
    }
}
"@
}

function Get-LLPowerSource {
    try {
        Ensure-LLNativePowerTypes
        $status = New-Object LidLess.SYSTEM_POWER_STATUS
        $ok = [LidLess.NativePower]::GetSystemPowerStatus([ref]$status)
        if ($ok -and $status.ACLineStatus -eq 0) {
            return "DC"
        }
    }
    catch {
        return "AC"
    }

    return "AC"
}

function New-LLPowerRequestHandle {
    param([string]$Reason)

    Ensure-LLNativePowerTypes

    $reasonPtr = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($Reason)
    try {
        $context = New-Object LidLess.REASON_CONTEXT
        $context.Version = [LidLess.NativePower]::POWER_REQUEST_CONTEXT_VERSION
        $context.Flags = [LidLess.NativePower]::POWER_REQUEST_CONTEXT_SIMPLE_STRING
        $context.SimpleReasonString = $reasonPtr

        $handle = [LidLess.NativePower]::PowerCreateRequest([ref]$context)
        $invalid = [IntPtr]::new(-1)
        if ($handle -eq [IntPtr]::Zero -or $handle -eq $invalid) {
            $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "PowerCreateRequest failed with Win32 error $err."
        }

        return $handle
    }
    finally {
        if ($reasonPtr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($reasonPtr)
        }
    }
}

function Set-LLThreadExecutionRequired {
    param([bool]$Enabled)

    Ensure-LLNativePowerTypes
    $flags = [LidLess.NativePower]::ES_CONTINUOUS
    if ($Enabled) {
        $flags = $flags -bor [LidLess.NativePower]::ES_SYSTEM_REQUIRED
    }

    [LidLess.NativePower]::SetThreadExecutionState($flags) | Out-Null
}

function Set-LLPowerRequestType {
    param(
        [int]$RequestType,
        [bool]$Enabled
    )

    if ($script:PowerRequestHandle -eq [IntPtr]::Zero) {
        throw "Power request handle is not open."
    }

    if ($Enabled) {
        $ok = [LidLess.NativePower]::PowerSetRequest($script:PowerRequestHandle, $RequestType)
    }
    else {
        $ok = [LidLess.NativePower]::PowerClearRequest($script:PowerRequestHandle, $RequestType)
    }

    if (-not $ok) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Power request operation failed for type $RequestType enabled=$Enabled with Win32 error $err."
    }
}

function Set-LLPowerRequest {
    param(
        [string]$Reason,
        [bool]$SystemRequired,
        [bool]$ExecutionRequired
    )

    Ensure-LLNativePowerTypes

    if (-not $SystemRequired -and -not $ExecutionRequired) {
        Clear-LLPowerRequest
        return
    }

    if ($script:PowerRequestHandle -eq [IntPtr]::Zero) {
        $script:PowerRequestHandle = New-LLPowerRequestHandle -Reason $Reason
    }

    if ($SystemRequired -ne $script:SystemRequestSet) {
        Set-LLPowerRequestType -RequestType ([LidLess.NativePower]::PowerRequestSystemRequired) -Enabled $SystemRequired
        $script:SystemRequestSet = $SystemRequired
    }

    if ($ExecutionRequired -ne $script:ExecutionRequestSet) {
        Set-LLPowerRequestType -RequestType ([LidLess.NativePower]::PowerRequestExecutionRequired) -Enabled $ExecutionRequired
        $script:ExecutionRequestSet = $ExecutionRequired
    }

    Set-LLThreadExecutionRequired -Enabled $SystemRequired
}

function Clear-LLPowerRequest {
    Ensure-LLNativePowerTypes

    if ($script:PowerRequestHandle -ne [IntPtr]::Zero) {
        if ($script:SystemRequestSet) {
            [LidLess.NativePower]::PowerClearRequest($script:PowerRequestHandle, [LidLess.NativePower]::PowerRequestSystemRequired) | Out-Null
        }
        if ($script:ExecutionRequestSet) {
            [LidLess.NativePower]::PowerClearRequest($script:PowerRequestHandle, [LidLess.NativePower]::PowerRequestExecutionRequired) | Out-Null
        }
        [LidLess.NativePower]::CloseHandle($script:PowerRequestHandle) | Out-Null
    }

    $script:PowerRequestHandle = [IntPtr]::Zero
    $script:SystemRequestSet = $false
    $script:ExecutionRequestSet = $false
    Set-LLThreadExecutionRequired -Enabled $false
}

function Get-LLPowerRequestState {
    return [pscustomobject]@{
        HasHandle = ($script:PowerRequestHandle -ne [IntPtr]::Zero)
        SystemRequired = $script:SystemRequestSet
        ExecutionRequired = $script:ExecutionRequestSet
    }
}

Export-ModuleMember -Function Get-LLPowerSource, Set-LLPowerRequest, Clear-LLPowerRequest, Get-LLPowerRequestState
