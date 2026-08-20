# clean_boot_ini.ps1
# Strips debug flags (/bootlog, /SOS) from an XP boot.ini.
# Keeps /fastdetect and /usepmtimer (usepmtimer fixes timer issues on nForce/AMD boards).
# File attributes (hidden/system) are preserved.
#
# Usage:
#   .\clean_boot_ini.ps1 -DriveLetter F

param(
    [string]$DriveLetter = 'F'
)

$L    = $DriveLetter[0]
$path = "$L`:\boot.ini"

if (-not (Test-Path -LiteralPath $path -Force)) { throw "boot.ini not found at $path" }

$attrs  = (Get-Item -LiteralPath $path -Force).Attributes
$lines  = Get-Content -LiteralPath $path -Force
$change = $false

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '/bootlog|/SOS') {
        $lines[$i] = ($lines[$i] -replace '\s*/bootlog\s*', ' ' -replace '\s*/SOS\s*', ' ').Trim()
        $change = $true
    }
}

if (-not $change) {
    "boot.ini is already clean - no changes made."
    Get-Content -LiteralPath $path -Force
    return
}

Set-Content -LiteralPath $path -Value $lines -Encoding ASCII
Get-Item -LiteralPath $path -Force | Set-ItemProperty -Name Attributes -Value $attrs

"boot.ini cleaned (debug flags removed):"
Get-Content -LiteralPath $path -Force