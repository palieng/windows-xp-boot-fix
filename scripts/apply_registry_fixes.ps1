# apply_registry_fixes.ps1
# Offline registry surgery on a broken XP install (run from the host):
#   1. CriticalDeviceDatabase: pci#cc_0101 -> Service=pciide, ClassGUID=SCSIAdapter
#      (lets the generic IDE driver claim ANY IDE-mode controller, e.g. nForce
#       SATA running in IDE/Legacy mode, which enumerates as PCI class 0101)
#   2. Services intelide + pciide -> Start=0 (load the IDE stack at boot)
# Applied to ControlSet001 and ControlSet002. Hives are loaded/unloaded cleanly.
#
# Usage:
#   .\apply_registry_fixes.ps1 -SystemDriveLetter F

param(
    [string]$SystemDriveLetter = 'F'
)

$L    = $SystemDriveLetter[0]
$hive = "$L`:\WINDOWS\system32\config"

foreach ($f in @('SYSTEM', 'SOFTWARE')) {
    if (-not (Test-Path "$hive\$f")) { throw "Missing hive: $hive\$f" }
}

reg.exe load HKLM\XP_SYS    "$hive\SYSTEM"   | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load of SYSTEM failed" }
reg.exe load HKLM\XP_SOFT   "$hive\SOFTWARE" | Out-Null
if ($LASTEXITCODE -ne 0) { reg.exe unload HKLM\XP_SYS | Out-Null; throw "reg load of SOFTWARE failed" }

$cddbClass = '{4D36E96A-E325-11CE-BFC1-08002BE10318}'

foreach ($cs in @('ControlSet001', 'ControlSet002')) {
    $k = "HKLM:\XP_SYS\$cs\Control\CriticalDeviceDatabase\pci#cc_0101"
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name 'Service'   -Value 'pciide'    -Type String
    Set-ItemProperty -Path $k -Name 'ClassGUID' -Value $cddbClass  -Type String
    "OK  CDDB $cs\pci#cc_0101 -> Service=pciide ClassGUID=$cddbClass"

    foreach ($svc in @('intelide', 'pciide')) {
        $sk = "HKLM:\XP_SYS\$cs\Services\$svc"
        if (Test-Path $sk) {
            Set-ItemProperty -Path $sk -Name 'Start' -Value 0 -Type DWord
            "OK  Services $cs\$svc Start=0"
        }
        else {
            "WARN Services $cs\$svc not found - skipped"
        }
    }
}

reg.exe unload HKLM\XP_SYS   | Out-Null
reg.exe unload HKLM\XP_SOFT  | Out-Null
"Done - hives unloaded."