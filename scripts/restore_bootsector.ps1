# restore_bootsector.ps1
# Rolls back the volume boot sector / BPB from a backup .bin created by
# backup_bootsector.ps1. Verifies the backup size, optionally its SHA256,
# writes it back, and confirms by reading the sector back.
#
# Usage:
#   .\restore_bootsector.ps1 -DriveLetter F -BackupPath backups\bootsector_20260820_013646.bin
#   .\restore_bootsector.ps1 -DriveLetter F -BackupPath <file> -BackupHash <sha256>

param(
    [string]$DriveLetter = 'F',
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [string]$BackupHash = ''
)

. "$PSScriptRoot\rawdisk_io.ps1"

if (-not (Test-Path -LiteralPath $BackupPath)) { throw "Backup not found: $BackupPath" }

$bak = [System.IO.File]::ReadAllBytes($BackupPath)
if ($bak.Length -ne 512) { throw "Backup is $($bak.Length) bytes - expected 512. Aborting." }

if ($BackupHash) {
    $actual = (Get-FileHash -LiteralPath $BackupPath -Algorithm SHA256).Hash
    if ($actual -ne $BackupHash.ToUpper()) { throw "SHA256 mismatch: backup may be corrupt. Aborting." }
    "SHA256 OK."
}

$device = "\\.\$($DriveLetter[0]):"
$cur    = Read-RawSectors -Device $device -Offset 0 -Length 512

$bakOem = [System.Text.Encoding]::ASCII.GetString($bak, 3, 8).TrimEnd([char]0)
$curOem = [System.Text.Encoding]::ASCII.GetString($cur, 3, 8).TrimEnd([char]0)

"Backup : $BackupPath (OEM '$bakOem')"
"Current: volume $($DriveLetter[0]): (OEM '$curOem')"

$ans = Read-Host "Overwrite the current boot sector with the backup? (y/N)"
if ($ans -ne 'y') { "Aborted - no changes made."; exit 1 }

try {
    Write-RawBytes -Device $device -Offset 0 -Data $bak
    "Write OK."
}
catch {
    "WRITE FAILED: $($_.Exception.Message)"
    exit 2
}

$chk = Read-RawSectors -Device $device -Offset 0 -Length 512
$same = $true
for ($i = 0; $i -lt 512; $i++) {
    if ($chk[$i] -ne $bak[$i]) { $same = $false; break }
}

if ($same) {
    "Verified - boot sector restored byte-for-byte."
}
else {
    "VERIFY FAILED - read-back differs from backup at byte $i."
    exit 3
}