# check_volume_state.ps1
# Reports the dirty flag of every mounted volume.
# A dirty volume makes XP run chkdsk at every boot until it is cleared.
# Clear with:  chkdsk X: /f
#
# Usage:
#   .\check_volume_state.ps1

$rows = foreach ($vol in Get-Volume) {
    if (-not $vol.DriveLetter) { continue }
    $dirty = (fsutil dirty query "$($vol.DriveLetter):" 2>&1 | Out-String) -notmatch 'NOT Dirty'
    [PSCustomObject]@{
        Drive = "$($vol.DriveLetter):"
        Label = $vol.FileSystemLabel
        FS    = $vol.FileSystem
        Dirty = $(if ($dirty) { 'YES' } else { 'no' })
    }
}
$rows | Format-Table -AutoSize

$dirtyRows = @($rows | Where-Object { $_.Dirty -eq 'YES' })
if ($dirtyRows.Count -gt 0) {
    "Dirty volume(s): $($dirtyRows.Drive -join ', ')  ->  run: chkdsk <letter>: /f"
}
else {
    "No dirty volumes - chkdsk will not run at boot."
}