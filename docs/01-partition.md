# Disk Partitioning (Btrfs + Snapper Layout)

This document describes the standard disk layout used for this system.

## Overview

We use:

* GPT partition table
* UEFI boot
* Btrfs for the main filesystem
* Subvolumes for clean snapshot management
* No swap partition (zram is used instead)

---

## Disk Layout

| Partition | Size  | Type  | Mount Point    |
| --------- | ----- | ----- | -------------- |
| p1        | 1 GiB | FAT32 | /efi           |
| p2        | rest  | Btrfs | / (subvolumes) |

---

## Why this layout?

* **Btrfs** → snapshots, compression, rollback
* **Subvolumes** → isolate system vs data
* **No swap partition** → avoids Btrfs complications
* **1 GiB EFI** → supports multiple kernels + future flexibility

---

## Step-by-step

### 1. Identify disk

```bash
lsblk
```

Example disk:

```text
/dev/nvme0n1
```

⚠️ Make sure this is correct — this will erase the disk.

---

### 2. Create partition table + partitions

```bash
parted /dev/nvme0n1 --script \
  mklabel gpt \
  mkpart ESP fat32 1MiB 1025MiB \
  set 1 esp on \
  mkpart primary 1025MiB 100%
```

---

### 3. Format partitions

```bash
mkfs.fat -F32 /dev/nvme0n1p1
mkfs.btrfs -f /dev/nvme0n1p2
```

---

## Btrfs Subvolume Layout

We create the following subvolumes:

| Subvolume  | Mount Point           | Purpose                             |
| ---------- | --------------------- | ----------------------------------- |
| @          | /                     | root filesystem                     |
| @home      | /home                 | user data                           |
| @snapshots | /.snapshots           | snapper snapshots                   |
| @log       | /var/log              | logs (excluded from root snapshots) |
| @pkg       | /var/cache/pacman/pkg | package cache                       |

---

### 4. Create subvolumes

```bash
mount /dev/nvme0n1p2 /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg

umount /mnt
```

---

## Mount Configuration

### 5. Mount root

```bash
mount -o subvol=@,noatime,compress=zstd:3 /dev/nvme0n1p2 /mnt
```

---

### 6. Create mount points

```bash
mkdir -p /mnt/{home,.snapshots,var/log,var/cache/pacman/pkg,efi}
```

---

### 7. Mount subvolumes

```bash
mount -o subvol=@home,noatime,compress=zstd:3 /dev/nvme0n1p2 /mnt/home
mount -o subvol=@snapshots,noatime,compress=zstd:3 /dev/nvme0n1p2 /mnt/.snapshots
mount -o subvol=@log,noatime,compress=zstd:3 /dev/nvme0n1p2 /mnt/var/log
mount -o subvol=@pkg,noatime,compress=zstd:3 /dev/nvme0n1p2 /mnt/var/cache/pacman/pkg
mount /dev/nvme0n1p1 /mnt/efi
```

---

## Mount Options Explained

* `compress=zstd:3` → good balance of speed + compression
* `noatime` → reduces unnecessary disk writes

---

## Swap Strategy

We do **not** create a swap partition.

Instead:

* use zram after install
* avoids Btrfs snapshot limitations
* simpler and faster for desktop use

---

## Final Layout

```text
/dev/nvme0n1p1   1 GiB      FAT32   /efi
/dev/nvme0n1p2   ~953 GiB   Btrfs

Subvolumes:
@           → /
@home       → /home
@snapshots  → /.snapshots
@log        → /var/log
@pkg        → /var/cache/pacman/pkg
```

---

## Notes

* Snapshots apply to `/` (system), not logs or cache
* `/home` is independent and not rolled back with system snapshots
* This layout is optimised for **Snapper + rollback safety**

---

## Next Step

Continue with:

* Base installation (`archinstall` minimal profile)
* Bootloader setup (systemd-boot)
* Snapper + zram configuration
