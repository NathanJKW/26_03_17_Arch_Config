# Base Installation (Arch + Minimal Profile)

This section covers installing Arch Linux using `archinstall` after the disk has been partitioned and mounted.

---

## Overview

At this stage:

* Disk is partitioned
* Btrfs subvolumes are created
* Filesystems are mounted under `/mnt`

We now install a **minimal Arch system** and leave all customisation to our repo.

---

## ⚠️ Important Approach

We use:

👉 `archinstall` **minimal profile**

We do **NOT**:

* use desktop profiles
* install Hyprland here
* install extra packages

👉 This keeps the base system clean and predictable.

---

## 1. Start the installer

From the Arch ISO:

```bash
archinstall
```

---

## 2. Key configuration choices

Follow the menu and set the following:

### Mirrors

* Choose your country (e.g. United Kingdom)

---

### Disk configuration

⚠️ Since we already partitioned manually:

* Select: **"Use existing partitions"**
* Assign:

  * Btrfs partition → `/`
  * EFI partition → `/efi`

Do NOT let archinstall repartition the disk.

---

### Filesystem

* Filesystem type: **btrfs**
* Mount point: `/`

(Subvolumes are already created — do not recreate them)

---

### Bootloader

Select:

```text
systemd-boot
```

👉 This is preferred for:

* simplicity
* reliability
* clean UEFI integration

---

### Swap

* Select: **None**

👉 We will configure zram later instead.

---

### Hostname

Set your machine name (e.g. `arch-desktop`)

---

### Root password

Set a secure password (or disable if you prefer sudo-only workflow)

---

### User account

Create your main user:

* username: e.g. `youruser`
* password: set
* grant sudo: **yes**

---

### Profile

Select:

```text
minimal
```

👉 This is critical — no preinstalled desktop environment.

---

### Audio

* You can skip or leave default (we configure PipeWire later)

---

### Networking

* Enable NetworkManager (recommended)

---

### Timezone / Locale

Set:

* timezone: e.g. `Europe/London`
* locale: e.g. `en_GB.UTF-8`
* keyboard: `uk` (if applicable)

---

## 3. Install

Confirm and let `archinstall` run.

This will:

* install base system
* configure bootloader
* generate fstab
* create user
* install kernel

---

## 4. Reboot

After install completes:

```bash
reboot
```

Remove the USB when prompted.

---

## 5. First boot checklist

Log in and verify:

### Internet

```bash
ping archlinux.org
```

---

### Disk layout

```bash
lsblk
```

Ensure:

* `/efi` is mounted
* Btrfs subvolumes are mounted correctly

---

### Btrfs mounts

```bash
mount | grep btrfs
```

You should see:

* `subvol=@`
* `subvol=@home`
* etc.

---

## ⚠️ If subvolumes are wrong

If `archinstall` did not respect subvolumes:

👉 STOP and fix before continuing

Your system must use:

* `@` for root
* `@home` for home

Otherwise snapshots will not behave correctly.

---

## 6. Install Git (required for next step)

```bash
sudo pacman -S git
```

---

## 7. Next step

Now move on to:

👉 Post-install setup:

* Snapper (snapshots)
* zram (swap)
* Hyprland + packages
* dotfiles via Stow

---

## Final state after this step

You now have:

* Minimal Arch system
* systemd-boot configured
* Btrfs filesystem mounted
* User + networking working

👉 Everything else is defined by your repo.

---

## Philosophy

This stage should remain:

* minimal
* reproducible
* disposable

👉 The system becomes “yours” only after post-install scripts run.
