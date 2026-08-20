# rawdisk_io.ps1
# Low-level raw sector read/write helpers.
# Dot-source this file, then call Read-RawSectors / Write-RawBytes.
#
# IMPORTANT: Windows rejects raw writes to an ONLINE (mounted) NTFS volume with
# ERROR_SHARING_VIOLATION. Take the disk offline first:
#   Set-Disk -Number <N> -IsOffline $true
#
# Example:
#   . .\rawdisk_io.ps1
#   $sector = Read-RawSectors -Device "\\.\F:" -Offset 0 -Length 512
#   Write-RawBytes -Device "\\.\F:" -Offset 0 -Data $sector

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RawIO {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateFile(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tpl);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetFilePointerEx(IntPtr h, long dist, out long newPos, uint move);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadFile(IntPtr h, byte[] buf, int n, out int read, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool WriteFile(IntPtr h, byte[] buf, int n, out int written, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr h);
}
'@

function Read-RawSectors {
    param(
        [string]$Device = '\\.\F:',
        [long]$Offset   = 0,
        [int]$Length    = 512
    )
    $h = [RawIO]::CreateFile($Device, 0x80000000, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h -eq [IntPtr](-1)) {
        throw "Cannot open $Device for reading (is the volume online/mounted?)"
    }
    try {
        $p = [IntPtr]::Zero
        [RawIO]::SetFilePointerEx($h, $Offset, [ref]$p, 0) | Out-Null
        $buf  = New-Object byte[] $Length
        $read = 0
        if (-not [RawIO]::ReadFile($h, $buf, $Length, [ref]$read, [IntPtr]::Zero)) {
            throw "ReadFile failed at offset $Offset"
        }
        if ($read -lt $Length) { $buf = $buf[0..($read - 1)] }
        return ,$buf
    }
    finally { [RawIO]::CloseHandle($h) | Out-Null }
}

function Write-RawBytes {
    param(
        [string]$Device = '\\.\F:',
        [long]$Offset   = 0,
        [byte[]]$Data
    )
    $h = [RawIO]::CreateFile($Device, 0x40000000, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h -eq [IntPtr](-1)) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($e -eq 32) {
            throw "WRITE BLOCKED: volume is ONLINE/mounted (ERROR_SHARING_VIOLATION). Take the disk offline first: Set-Disk -Number <N> -IsOffline `$true"
        }
        throw ("Cannot open {0} for writing (err 0x{1:X8})" -f $Device, $e)
    }
    try {
        $p = [IntPtr]::Zero
        [RawIO]::SetFilePointerEx($h, $Offset, [ref]$p, 0) | Out-Null
        $written = 0
        if (-not [RawIO]::WriteFile($h, $Data, $Data.Length, [ref]$written, [IntPtr]::Zero)) {
            throw "WriteFile failed at offset $Offset"
        }
        if ($written -ne $Data.Length) {
            throw "Short write: $written of $($Data.Length) bytes"
        }
    }
    finally { [RawIO]::CloseHandle($h) | Out-Null }
}

Write-Host "rawdisk_io.ps1 loaded: Read-RawSectors / Write-RawBytes available."