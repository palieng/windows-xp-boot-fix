# backup_bootsector.ps1
# Backs up the first 512 bytes (volume boot sector / BPB) of a volume.
# Run this BEFORE any raw patching, and keep the .bin until the machine is stable.
#
# Usage:
#   .\backup_bootsector.ps1 -DriveLetter F

param(
    [string]$DriveLetter = 'F',
    [string]$OutputPath  = "$PSScriptRoot\..\backups\bootsector_$(Get-Date -Format 'yyyyMMdd_HHmmss').bin"
)

. "$PSScriptRoot\rawdisk_io.ps1"

$device = "\\.\$($DriveLetter[0]):"
$sector = Read-RawSectors -Device $device -Offset 0 -Length 512

$dir = Split-Path $OutputPath -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

[System.IO.File]::WriteAllBytes($OutputPath, $sector)
$hash = (Get-FileHash $OutputPath -Algorithm SHA256).Hash
$oem  = [System.Text.Encoding]::ASCII.GetString($sector, 3, 8).TrimEnd([char]0)

"Backup written : $OutputPath ($($sector.Length) bytes, OEM '$oem')"
"SHA256         : $hash"