# Windows XP 0x000000ED Boot Fix — disk moved to new hardware

**Making a legacy Windows XP install boot — and behave — after its disk lands on new hardware.**
No reinstall. No warez activation cracks. No boot-loop despair. Tested in the field on a Gigabyte GA-M720-ES3 (NVIDIA nForce 720a).

```
STOP: 0x000000ED (0xFFFFFAD3, 0xC0000015, ...)      <- won't even boot
"Windows needs to be activated"                      <- won't even shut up
```

This repo is the battle-tested playbook for both.

---

## Table of contents

1. [The problem](#the-problem)
2. [How this works](#how-this-works)
3. [Requirements](#requirements)
4. [Safety first](#safety-first)
5. [Step 1 — Gather facts](#step-1--gather-facts)
6. [Step 2 — Back up the boot sector](#step-2--back-up-the-boot-sector)
7. [Step 3 — Diagnose in a VM (and the 0xED write-lock trap)](#step-3--diagnose-in-a-vm-and-the-0xed-write-lock-trap)
8. [Step 4 — Registry surgery for the new chipset](#step-4--registry-surgery-for-the-new-chipset)
9. [Step 5 — Activation the honest way](#step-5--activation-the-honest-way)
10. [Step 6 — Cleanup](#step-6--cleanup)
11. [Scripts](#scripts)
12. [Acceptance checklist](#acceptance-checklist)
13. [Rollback](#rollback)
14. [Appendix — Mapping the physical disk to a VM](#appendix--mapping-the-physical-disk-to-a-vm)
15. [FAQ](#faq)
16. [Persian version](#persian-version)
17. [License](#license)

---

## The problem

An old machine dies. You yank its XP drive and plug it into a newer board. What you get:

| Symptom | Cause |
|---|---|
| `STOP 0x000000ED` / `0xC0000015` at boot | NTFS can't complete boot-time writes. Either a host-side write lock (see Step 3) or the new SATA controller isn't claimed by any driver (see Step 4). |
| Boots, then demands activation | WPA tripped on the hardware change. |
| `chkdsk` runs at every boot | Dirty volume flag from hard power-offs. |
| Slow / timer glitches | nForce boards + bad timer source (fixed by `/usepmtimer`). |

Everything below is done **offline, from a Windows 10/11 host**, except where noted.

---

## How this works

1. Back up the boot sector before touching anything.
2. Prove the install is bootable by testing in a VM (with a critical host-side gotcha).
3. Patch the filesystem **and** the registry so the new chipset can drive the disk (IDE/Legacy mode + generic IDE driver).
4. Boot it, activate it with a cryptographically valid Confirmation ID (no cracks).
5. Clean up all the diagnostic residue.

---

## Requirements

- A Windows 10/11 host with PowerShell (admin).
- The XP disk attached to the host (USB dock or SATA).
- The drive letter of the XP system partition (in this guide: `F:`).
- ~1 hour and steady hands.
- **BIOS note:** the new board's SATA must be in **IDE/Legacy mode** (not AHCI/RAID). This guide targets that setup.

---

## Safety first

- Raw sector writes can destroy a filesystem. **Always run the backup script first.**
- Keep the backup `.bin` until the machine has booted successfully several times on the real hardware.
- Never raw-write while the target volume is online/mounted — Windows rejects the write (and a half-applied patch is worse than none). Take the disk offline first.
- Verify every patch by reading it back (all scripts do this).
- `diskpart` + `clean` on the wrong disk = your week is ruined. Double-check `Get-Disk` before anything.

---

## Step 1 — Gather facts

Identify the disk and its partitions, and note the geometry of the XP system partition:

```powershell
Get-Disk | Format-Table Number, FriendlyName, Size, PartitionStyle
Get-Partition -DiskNumber <N> | Format-Table PartitionNumber, DriveLetter, Type, Size
Get-Volume | Format-Table DriveLetter, FileSystemLabel, FileSystem, HealthStatus, Size
```

Record: partition size in bytes, bytes/sector (usually 512), sectors/cluster (usually 8 for NTFS).

Check the dirty flag and snapshot the boot config:

```powershell
fsutil dirty query F:
type F:\boot.ini
```

---

## Step 2 — Back up the boot sector

```powershell
.\scripts\backup_bootsector.ps1 -DriveLetter F
```

Writes `backups\bootsector_<timestamp>.bin` (512 bytes, the volume boot sector / BPB) and prints its SHA256. Keep this file until the machine is stable.

---

## Step 3 — Diagnose in a VM (and the 0xED write-lock trap)

Map the physical disk into a VM (VMware rawdisk / VirtualBox raw VMDK / Hyper-V pass-through) and boot the XP install there. This lets you iterate on fixes without rebooting the physical machine.

### The trap we hit (proven by isolation testing)

- **Boot A (volume OFFLINE on the host):** XP boots to the desktop. Writes succeed.
- **Boot B (volume ONLINE/mounted on the host):** same disk, same patches → `STOP 0x000000ED, param2 0xC0000015`.

**Root cause:** while the disk is attached to a Windows host, an *online* NTFS volume is held with an exclusive write lock. XP's boot-time writes then fail → 0xED. It is **not** a VM-only problem in the "VMware is broken" sense — it's the host locking the disk.

**Rule:** before booting the VM, take the disk offline on the host:

```powershell
Set-Disk -Number <N> -IsOffline $true
# (after the test: Set-Disk -Number <N> -IsOffline $false)
```

### If 0xED persists with the disk offline

The NTFS boot sector's `TotalSectors64` field (offset `0x28`) may be zeroed or stale (e.g., copied from a FAT install, or a half-written geometry). XP then reads a nonsense volume size and can't find its files.

```powershell
.\scripts\patch_bpb_sectors.ps1 -DriveLetter F
```

The script prints the current vs. expected value and patches it (expected = volume size ÷ bytes/sector, auto-computed). It reads the result back to verify.

**VM reaches the desktop → the install is sound.** The remaining physical-boot failure is the SATA driver stack → Step 4.

---

## Step 4 — Registry surgery for the new chipset

XP boots on the real board but the old driver stack doesn't know the new SATA controller. Two-part fix, done offline on the hives:

1. **Critical Device Database (CDDB):** tell the generic IDE driver (`pciide`) to claim *any* IDE-mode controller. The nForce 720a SATA in IDE mode enumerates with PCI class code `0101` (IDE controller), so add:

   ```
   HKLM\SYSTEM\ControlSet00X\Control\CriticalDeviceDatabase\pci#cc_0101
       Service   = "pciide"
       ClassGUID = "{4D36E96A-E325-11CE-BFC1-08002BE10318}"   (SCSIAdapter class)
   ```

2. **Services:** make the IDE stack load at boot (`Start = 0`):

   ```
   HKLM\SYSTEM\ControlSet00X\Services\intelide  Start = 0
   HKLM\SYSTEM\ControlSet00X\Services\pciide    Start = 0
   ```

One command does both (adds to `ControlSet001` and `ControlSet002`, loads/unloads the hives cleanly):

```powershell
.\scripts\apply_registry_fixes.ps1 -SystemDriveLetter F
```

> Verify on the target board (before or after): the SATA controller must enumerate as class `0101` with the *generic* IDE driver bound — no `nvata`/`nvgts`/`nvraid` services present, no AHCI/RAID mode.

### Identifying what your board enumerates

From any Windows running on the target board, list the PCI devices and check the SATA controller's class code:

```powershell
wmic path Win32_PnPEntity where "DeviceID like 'PCI%'" get DeviceID, Name /format:list
```

Reference values (nForce 720a, IDE/Legacy mode, tested in the field):

```
PCI\VEN_10DE&DEV_0759  -> NVIDIA nForce 720a/730a SATA   (class 0101, IDE controller)
PCI\VEN_10DE&DEV_0AD0  -> NVIDIA nForce 720a PATA        (class 0101, IDE controller)
```

Both bind to the generic "Standard Dual Channel PCI IDE Controller" (`pci\cc_0101`), and **no** `nvata`/`nvgts`/`nvraid` service exists. That is exactly the situation the CDDB entry above is for.

Class-code quick reference: `0101` = IDE controller (this guide), `0106` = AHCI, `0104` = RAID. If you see `0106`/`0104`, switch the board to IDE/Legacy mode in the BIOS — this guide does not cover AHCI/RAID driver injection.

---

## Step 5 — Activation the honest way

The hardware change trips Windows Product Activation. The nag can be killed two ways — **only one of them is permanent**:

### ❌ The magic-reg-file way (don't)

Setting `OOBETimer` to the famous `FFD571D68B6A8D6FD53393FD` + a "patched" `DigitalProductId` **does not survive this hardware** (we tested it twice):

1. Boot → WPA regenerates a fresh `OOBETimer` → state reverts.
2. Patch the SYSTEM-hive mirror too → WPA now reports the state as **corrupted** and blocks at the error screen.

That route is a dead end on nForce-class boards with a dead CMOS clock.

### ✅ The Confirmation ID way (permanent, no cracks)

Windows phone activation generates a **Confirmation ID** from the machine's **Installation ID**. The algorithm (hyperelliptic-curve math inside `licdll.dll`) was reverse-engineered and implemented as open-source tools. Entering a valid Confirmation ID is a *real* activation — WPA accepts it forever, no re-init, no nag, no balloon.

1. Boot the machine → the activation wizard shows the **Installation ID** (54 digits, 9 groups of 6, e.g. `123456-789012-345678-...`).
2. Generate the **Confirmation ID** with either tool (open source, run on the host or the XP box):
   - [Alex313031/xp_activate32](https://github.com/Alex313031/xp_activate32) — GUI, releases include prebuilt `.exe`
   - [Endermanch/XPConfirmationIDKeygen](https://github.com/Endermanch/XPConfirmationIDKeygen) — the original
3. Enter the Confirmation ID in the wizard → **activated, permanently.**

The keygen computes the Confirmation ID **locally** from the Installation ID — it needs neither the XP machine nor Microsoft's servers, so it runs fine on the host. The GUI's "activate/deposit" button only works on the XP box itself (it talks to the local `licdll.dll`); on the host, simply copy the generated code into the activation wizard.

Use it only for machines you own and hold a license for.

---

## Step 6 — Cleanup

Once the machine is stable:

- **boot.ini** — strip the debug flags left over from diagnostics:
  ```powershell
  .\scripts\clean_boot_ini.ps1 -DriveLetter F
  ```
  Removes `/bootlog` and `/SOS`; keeps `/fastdetect` and `/usepmtimer` (the latter fixes timer issues on nForce/AMD boards).

- **Dirty flag** — if the volume is dirty, `chkdsk` will run at every boot until it's cleared:
  ```powershell
  .\scripts\check_volume_state.ps1
  chkdsk F: /f        # only if it reports dirty
  ```

- Delete leftover artifacts: `ntbtlog.txt` (only exists if `/bootlog` is set), test VHDs, etc.

- **Verify everything** in one go:
  ```powershell
  .\scripts\verify_fixes.ps1 -DriveLetter F
  ```

---

## Scripts

| Script | What it does |
|---|---|
| `scripts/rawdisk_io.ps1` | Low-level raw sector read/write helpers (dot-source). Refuses writes with a clear message when the volume is online. |
| `scripts/backup_bootsector.ps1` | Backs up the volume boot sector (+SHA256) before any patching. |
| `scripts/restore_bootsector.ps1` | Rolls back the boot sector/BPB from a backup `.bin` (verifies size + optional SHA256, then read-back check). |
| `scripts/patch_bpb_sectors.ps1` | Prints NTFS BPB geometry; patches `TotalSectors64` (offset 0x28) if wrong; verifies by read-back. |
| `scripts/apply_registry_fixes.ps1` | Offline: adds CDDB `pci#cc_0101 → pciide` and sets `intelide`/`pciide` `Start=0` in both control sets. |
| `scripts/check_volume_state.ps1` | Reports the dirty flag of every volume. |
| `scripts/clean_boot_ini.ps1` | Removes `/bootlog` `/SOS` from `boot.ini`, preserves file attributes. |
| `scripts/verify_fixes.ps1` | End-to-end check: boot files, boot.ini flags, CDDB entry, service Start values, dirty flag. |

---

## Acceptance checklist

Walk through this before calling it done:

- [ ] VM boot (disk **offline** on the host) reaches the desktop
- [ ] Physical boot on the target board reaches the desktop
- [ ] Activation: Confirmation ID accepted, no nag after a reboot
- [ ] No `chkdsk` at boot (volume not dirty)
- [ ] `verify_fixes.ps1 -DriveLetter F` passes all checks
- [ ] boot.ini has no `/bootlog` `/SOS`
- [ ] Boot-sector backup kept until several successful boots

---

## Rollback

Every step is reversible:

- **Boot sector / BPB** → restore from backup:
  ```powershell
  .\scripts\restore_bootsector.ps1 -DriveLetter F -BackupPath backups\bootsector_<timestamp>.bin
  ```
- **Registry fixes** → delete `ControlSet00X\Control\CriticalDeviceDatabase\pci#cc_0101` and set the `intelide`/`pciide` `Start` values back to what they were (record them before running the fix script).
- **Activation** → it's a real activation; there is nothing to undo. If you used the reg-hack instead and ended up stuck, see the FAQ.

---

## Appendix — Mapping the physical disk to a VM

You need a raw (pass-through) disk in the VM so XP boots the physical install. With the disk attached to the host:

**VirtualBox** (run as admin — the disk must be offline/unmounted first):

```powershell
VBoxManage internalcommands createrawvmdk `
    -filename "C:\vm\xpdisk.vmdk" -rawdisk \\.\PhysicalDrive<N>
```

Then attach `xpdisk.vmdk` as the VM's SATA/IDE disk. Do **not** let the host mount the XP volumes while the VM is running (see Step 3).

**VMware Workstation:** create a raw-disk descriptor `xpdisk.vmdk` with the physical disk's geometry:

```
# Disk DescriptorFile
version=1
CID=ffffffff
parentCID=ffffffff
createType="fullDevice"

# Extent description
RW 3907029168 FLAT "\\.\PhysicalDrive<N>" 0

# The Disk Data Base
ddb.virtualHWVersion = "7"
ddb.geometry.cylinders = "<cylinders>"
ddb.geometry.heads = "16"
ddb.geometry.sectors = "63"
```

(Adjust the extent size and geometry to your disk: `Get-Disk` + `Get-Partition` show size; `heads=16, sectors=63`, `cylinders = size / 512 / 63 / 16`.) Then add the `.vmdk` to the VM.

**Hyper-V:** `Add-VMHardDiskDrive -VMName <vm> -Path \\.\PhysicalDrive<N>` (pass-through).

In all cases: the VM must boot the **same** partition the board will boot. Keep the disk **offline** on the host during VM boots (`Set-Disk -Number <N> -IsOffline $true`).

---

## FAQ

**Q: I still get 0xED with the disk offline in the VM.**
A: Patch the BPB (`patch_bpb_sectors.ps1`). If it's already correct, check `ntldr`/`NTDETECT.COM` are present and the boot.ini ARC path matches the actual partition (`partition(1)` etc.).
**Q: It boots but shows "It's now safe to turn off your computer".**

A: This install runs the non-ACPI "Standard PC" HAL inherited from the old machine. Swapping to ACPI is possible in theory, but on this stripped build it blue-screened even via `hal.inf` and `/hal=`/`/kernel=` boot.ini tricks, so it's intentionally left out of this playbook. The machine works fine; it just can't power off automatically.

**Q: Will the activation nag come back?**
A: With a real Confirmation ID — no. The whole point of Step 5 is that WPA stores a valid activation.

**Q: chkdsk runs at every boot.**
A: Dirty flag — see Step 6.

**Q: Can I use this on an AHCI/RAID board?**
A: The registry fix targets IDE/Legacy mode (class 0101). For AHCI you'd need the board's AHCI driver baked into the install, which is a different (harder) story.

**Q: My board is Intel/AMD, not nForce.**
A: The steps are chipset-agnostic; only the `/usepmtimer` note and the CDDB entry specifics change (verify your controller's class code).

**Q: I tried the OOBETimer/DPID reg-hack first and now XP is stuck on an activation error screen.**
A: Undo the hack: restore the hives from a pre-hack backup (or set `DigitalProductId`/`OOBETimer` back to their original values and delete `wpa.dbl`), boot once to let WPA rebuild a clean state, then use the Confirmation ID path in Step 5. Don't fight the state machine — replace it with a real activation.

**Q: A "your Windows is not genuine" balloon appears even after activation.**
A: That's WGA, a separate check on the product key (not the WPA state). Verify with Microsoft's `MGADiag.exe` (signed tool). With a real activation and a legitimate OEM key it normally clears itself; if it persists, the key itself is on a blocked list and only a different licensed key fixes it.

**Q: Does the keygen have to run on the XP machine?**
A: No — it computes the Confirmation ID locally from the Installation ID on any Windows box. Only the "activate/deposit" button inside the GUI needs XP (it writes into the local `licdll.dll`); you can equally just type the generated code into the activation wizard.

**Q: I don't know which SATA mode my board is in.**
A: Run the wmic query from Step 4 on the board: class `0101` = IDE/Legacy (this guide applies), `0106` = AHCI (needs driver injection — not covered), `0104` = RAID (not covered).

---

## Persian version

[README.fa.md](README.fa.md) — راهنمای کامل به فارسی

---

## License

MIT — see [LICENSE](LICENSE). Provided as-is; you are responsible for your own disks. Use it on hardware you own, with licenses you own.