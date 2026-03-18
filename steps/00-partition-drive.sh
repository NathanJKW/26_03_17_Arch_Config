#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/nvme0n1"
EFI_SIZE_MIB=1024

TEMP_MOUNT="/tmp/arch-btrfs-setup"
INSTALL_MOUNT="/mnt"

fail() {
  echo "FAIL"
  exit 1
}

trap fail ERR

partition_path() {
  local num="$1"
  if [[ "$DISK" =~ [0-9]$ ]]; then
    echo "${DISK}p${num}"
  else
    echo "${DISK}${num}"
  fi
}

cleanup() {
  set +e
  umount "${TEMP_MOUNT}" 2>/dev/null
  rmdir "${TEMP_MOUNT}" 2>/dev/null
}
trap cleanup EXIT

main() {
  local efi_end efi_part btrfs_part

  efi_end=$((1 + EFI_SIZE_MIB))
  efi_part="$(partition_path 1)"
  btrfs_part="$(partition_path 2)"

  parted "$DISK" --script \
    mklabel gpt \
    mkpart ESP fat32 1MiB "${efi_end}MiB" \
    set 1 esp on \
    mkpart primary btrfs "${efi_end}MiB" 100%

  partprobe "$DISK" || true
  sleep 1

  mkfs.fat -F32 "$efi_part"
  mkfs.btrfs -f "$btrfs_part"

  mkdir -p "$TEMP_MOUNT"
  mount "$btrfs_part" "$TEMP_MOUNT"

  btrfs subvolume create "$TEMP_MOUNT/@"
  btrfs subvolume create "$TEMP_MOUNT/@home"
  btrfs subvolume create "$TEMP_MOUNT/@snapshots"
  btrfs subvolume create "$TEMP_MOUNT/@log"
  btrfs subvolume create "$TEMP_MOUNT/@pkg"

  umount "$TEMP_MOUNT"

  mount -o subvol=@,noatime,compress=zstd "$btrfs_part" "$INSTALL_MOUNT"
  mkdir -p "$INSTALL_MOUNT/home"
  mkdir -p "$INSTALL_MOUNT/.snapshots"
  mkdir -p "$INSTALL_MOUNT/var/log"
  mkdir -p "$INSTALL_MOUNT/var/cache/pacman/pkg"
  mkdir -p "$INSTALL_MOUNT/boot"

  mount -o subvol=@home,noatime,compress=zstd "$btrfs_part" "$INSTALL_MOUNT/home"
  mount -o subvol=@snapshots,noatime,compress=zstd "$btrfs_part" "$INSTALL_MOUNT/.snapshots"
  mount -o subvol=@log,noatime,compress=zstd "$btrfs_part" "$INSTALL_MOUNT/var/log"
  mount -o subvol=@pkg,noatime,compress=zstd "$btrfs_part" "$INSTALL_MOUNT/var/cache/pacman/pkg"
  mount "$efi_part" "$INSTALL_MOUNT/boot"

  echo "PASS"
}

main