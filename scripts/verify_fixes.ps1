# verify_fixes.ps1
# End-to-end verification after applying all fixes:
#   boot files present, boot.ini clean, CDDB entry set, IDE services Start=0,
#   volume not dirty. Prints OK/FAIL per check, exit code 0 only if all pass.
#
# Usage:
#   .\verify_fixes.ps1 -DriveLetter F

param(
    [string]$DriveLetter = 'F'
)

$L    = $DriveLetter[0]
$fail = 0

Write-Host "== 1. Boot files =="
foreach ($f in @('ntldr', 'NTDETECT.COM', 'boot.ini')) {
    if (Test-Path "$L`:\$f" -Force) { "OK   $L\$f" } else { "FAIL $L\$f missing"; $fail++ }
}

Write-Host "`n== 2. boot.ini flags =="
$bi = Get-Content "$L`:\boot.ini" -Force -Raw
if ($bi -match '/bootlog|/SOS') { "FAIL boot.ini still has debug flags"; $fail++ } else { "OK   boot.ini clean" }

Write-Host "`n== 3. CDDB + services (offline hive) =="
reg.exe load HKLM\XP_SYS "$L`:\WINDOWS\system32\config\SYSTEM" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load of SYSTEM failed" }
foreach ($cs in @('ControlSet001', 'ControlSet002')) {
    $p = Get-ItemProperty "HKLM:\XP_SYS\$cs\Control\CriticalDeviceDatabase\pci#cc_0101" -ErrorAction SilentlyContinue
    if ($p -and $p.Service -eq 'pciide' -and $p.ClassGUID -eq '{4D36E96A-E325-11CE-BFC1-08002BE10318}') {
        "OK   CDDB $cs\pci#cc_0101 -> pciide"
    }
    else {
        "FAIL CDDB $cs\pci#cc_0101 missing or wrong"; $fail++
    }
    foreach ($svc in @('intelide', 'pciide')) {
        $s = (Get-ItemProperty "HKLM:\XP_SYS\$cs\Services\$svc" -ErrorAction SilentlyContinue).Start
        if ($s -eq 0) { "OK   $cs\Services\$svc Start=0" } else { "FAIL $cs\Services\$svc Start=$s"; $fail++ }
    }
}
reg.exe unload HKLM\XP_SYS | Out-Null

Write-Host "`n== 4. Volume dirty flag =="
$d = fsutil dirty query "$L`:" 2>&1 | Out-String
if ($d -match 'NOT Dirty') { "OK   $L`: not dirty" } else { "FAIL $L`: dirty (chkdsk will run at boot)"; $fail++ }

Write-Host ""
if ($fail -eq 0) { "ALL CHECKS PASSED" } else { "$fail check(s) FAILED - review the lines above" }
exit $fail