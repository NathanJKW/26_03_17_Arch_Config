# Post-Install Verification (Critical Checks)

This section ensures your system is correctly configured **before proceeding**.

Do NOT skip this — most issues later come from mistakes here.

---

## Overview

We verify:

* Bootloader (systemd-boot)
* EFI mount
* Btrfs subvolumes
* Mount options
* fstab correctness

---

# 🧪 1. Verify bootloader

Check boot entries:

```bash
bootctl status
```

Expected output includes:

```text
System:
    Firmware: UEFI
    Boot Loader: systemd-boot
```

And:

```text
Current Boot Loader:
    Product: systemd-boot
```

---

## Check loader entries

```bash
ls /efi/loader/entries/
```

You should see something like:

```text
arch.conf
```

---

## Inspect entry

```bash
cat /efi/loader/entries/arch.conf
```

Expected:

```text
options root=UUID=... rootflags=subvol=@ rw
```

⚠️ **Important**

* Must include: `rootflags=subvol=@`
* If missing → system will not boot correctly with snapshots

---

# 🧪 2. Verify EFI mount

```bash
lsblk
```

You should see:

```text
nvme0n1p1   vfat   mounted at /efi
```

Also verify:

```bash
mount | grep /efi
```

---

# 🧪 3. Verify Btrfs subvolumes

```bash
sudo btrfs subvolume list /
```

Expected:

```text
@ 
@home
@snapshots
@log
@pkg
```

---

# 🧪 4. Verify mount layout

```bash
mount | grep btrfs
```

Expected:

```text
subvol=@          → /
subvol=@home      → /home
subvol=@snapshots → /.snapshots
subvol=@log       → /var/log
subvol=@pkg       → /var/cache/pacman/pkg
```

---

# 🧪 5. Verify mount options

Each mount should include:

```text
noatime,compress=zstd
```

Check:

```bash
findmnt -no OPTIONS /
```

---

# 🧪 6. Verify fstab

Open:

```bash
cat /etc/fstab
```

Expected structure:

```text
UUID=xxxx /               btrfs subvol=@,noatime,compress=zstd:3 0 0
UUID=xxxx /home           btrfs subvol=@home,noatime,compress=zstd:3 0 0
UUID=xxxx /.snapshots     btrfs subvol=@snapshots,noatime,compress=zstd:3 0 0
UUID=xxxx /var/log        btrfs subvol=@log,noatime,compress=zstd:3 0 0
UUID=xxxx /var/cache/pacman/pkg btrfs subvol=@pkg,noatime,compress=zstd:3 0 0
UUID=xxxx /efi            vfat  defaults 0 2
```

---

## ⚠️ Common mistakes

### ❌ Wrong subvolume

```text
subvol=/   ← WRONG
```

Must be:

```text
subvol=@
```

---

### ❌ Missing mounts

If `/home` is not a subvolume:
→ snapshots will include user data (not desired)

---

### ❌ Missing compression

```text
compress=zstd
```

Should be present.

---

# 🧪 7. Verify networking

```bash
systemctl status NetworkManager
```

Should be:

```text
active (running)
```

---

# 🧪 8. Verify user sudo

```bash
sudo whoami
```

Expected:

```text
root
```

---

# 🧪 9. Quick sanity test

Reboot once:

```bash
reboot
```

Then verify:

* system boots cleanly
* no emergency shell
* user login works
* network connects

---

# 🚨 If something is wrong

## Fix fstab

Edit:

```bash
sudo nano /etc/fstab
```

Then:

```bash
sudo mount -a
```

---

## Fix boot entry

Edit:

```bash
sudo nano /efi/loader/entries/arch.conf
```

Ensure:

```text
rootflags=subvol=@
```

Then:

```bash
bootctl update
```

---

## Fix mounts manually

Example:

```bash
sudo mount -o subvol=@ /dev/nvme0n1p2 /
```

---

# ✅ Final checklist

You are ready to continue ONLY if:

* [ ] systemd-boot working
* [ ] `/efi` mounted correctly
* [ ] all Btrfs subvolumes present
* [ ] mounts use correct subvolumes
* [ ] compression enabled
* [ ] fstab matches layout
* [ ] system reboots cleanly

---

# Next Step

Proceed to:

👉 Snapper + zram setup
👉 Hyprland install
👉 Dotfiles (Stow)

---

## Philosophy

This step guarantees:

* your system is reproducible
* rollback will work correctly
* future debugging is predictable

👉 If this is correct, everything else becomes easy.
