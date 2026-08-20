# patch_bpb_sectors.ps1
# Inspects the NTFS BPB of a volume and patches TotalSectors64 (offset 0x28) if it
# is wrong (zeroed or stale). A wrong value makes XP read a nonsense volume size
# and fail with STOP 0x000000ED even when the disk is otherwise fine.
#
# Usage:
#   .\patch_bpb_sectors.ps1 -DriveLetter F
#   .\patch_bpb_sectors.ps1 -DriveLetter F -ExpectedTotalSectors64 81915372
#
# The expected value defaults to (volume size / bytes-per-sector), auto-computed.

param(
    [string]$DriveLetter = 'F',
    [long]$ExpectedTotalSectors64 = 0
)

. "$PSScriptRoot\rawdisk_io.ps1"

$device = "\\.\$($DriveLetter[0]):"
$b      = Read-RawSectors -Device $device -Offset 0 -Length 512

$bps     = [BitConverter]::ToUInt16($b, 0x0B)
$spc     = $b[0x0D]
$total32 = [BitConverter]::ToUInt32($b, 0x20)
$total64 = [BitConverter]::ToInt64($b, 0x28)
$oem     = [System.Text.Encoding]::ASCII.GetString($b, 3, 8).TrimEnd([char]0)

"Volume          : $($DriveLetter[0]):"
"OEM id          : $oem"
"BytesPerSector  : $bps"
"SectorsPerCluster: $spc"
"TotalSectors32  : $total32"
"TotalSectors64  : $total64"

if ($ExpectedTotalSectors64 -eq 0) {
    $vol = Get-Volume -DriveLetter $DriveLetter
    if (-not $vol -or $vol.Size -le 0) { throw "Cannot auto-compute volume size. Pass -ExpectedTotalSectors64 explicitly." }
    $ExpectedTotalSectors64 = [long]($vol.Size / $bps)
    "Expected (auto) : $ExpectedTotalSectors64  (= $($vol.Size) bytes / $bps)"
} else {
    "Expected        : $ExpectedTotalSectors64"
}

if ($total64 -eq $ExpectedTotalSectors64) {
    "OK - TotalSectors64 is already correct. Nothing to patch."
    exit 0
}

$ans = Read-Host "Patch TotalSectors64 from $total64 to $ExpectedTotalSectors64? (y/N)"
if ($ans -ne 'y') { "Aborted - no changes made."; exit 1 }

$new = [BitConverter]::GetBytes($ExpectedTotalSectors64)
[Array]::Copy($new, 0, $b, 0x28, 8)

try {
    Write-RawBytes -Device $device -Offset 0 -Data $b
    "Write OK."
}
catch {
    "WRITE FAILED: $($_.Exception.Message)"
    exit 2
}

$chk = Read-RawSectors -Device $device -Offset 0 -Length 512
$v   = [BitConverter]::ToInt64($chk, 0x28)
if ($v -eq $ExpectedTotalSectors64) {
    "Verified - TotalSectors64 is now $v."
}
else {
    "VERIFY FAILED - read back $v."
    exit 3
}