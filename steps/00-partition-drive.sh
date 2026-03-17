#!/usr/bin/env bash
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# ============================================================================
# Configuration (Fixed for this setup)
# ============================================================================
readonly EFI_OPTIONS=(512 1024 2048)  # MiB options
readonly EFI_DEFAULT=1024              # Default: 1 GiB
readonly MNT_TEMP="/tmp/arch_format_mnt"
readonly SUBVOLS=("@" "@home" "@snapshots" "@log" "@pkg")
readonly REQUIRED_COMMANDS=(parted lsblk mkfs.fat mkfs.btrfs blkid btrfs mount umount mountpoint findmnt)

# ============================================================================
# Cleanup on exit/error
# ============================================================================
cleanup() {
  local exit_code=$?
  log "Cleaning up..."
  
  # Unmount all temporary mounts (reverse order)
  if mountpoint -q "${MNT_TEMP}/var/cache/pacman/pkg" 2>/dev/null; then
    umount "${MNT_TEMP}/var/cache/pacman/pkg" 2>/dev/null || true
  fi
  if mountpoint -q "${MNT_TEMP}/var/log" 2>/dev/null; then
    umount "${MNT_TEMP}/var/log" 2>/dev/null || true
  fi
  if mountpoint -q "${MNT_TEMP}/.snapshots" 2>/dev/null; then
    umount "${MNT_TEMP}/.snapshots" 2>/dev/null || true
  fi
  if mountpoint -q "${MNT_TEMP}/home" 2>/dev/null; then
    umount "${MNT_TEMP}/home" 2>/dev/null || true
  fi
  if mountpoint -q "${MNT_TEMP}" 2>/dev/null; then
    umount "${MNT_TEMP}" 2>/dev/null || true
  fi
  
  # Remove temp directory if empty
  [[ -d "${MNT_TEMP}" ]] && rmdir "${MNT_TEMP}" 2>/dev/null || true
  
  [[ $exit_code -eq 0 ]] || log "Script exited with error code: $exit_code"
  return $exit_code
}
trap cleanup EXIT

# ============================================================================
# Interactive Functions
# ============================================================================

confirm() {
  local prompt="$1"
  local response
  
  while true; do
    read -r -p "$prompt (Y/n): " response
    response="${response:-Y}"
    case "$response" in
      [Yy]) return 0 ;;
      [Nn]) return 1 ;;
      *) echo "Please answer Y or N" ;;
    esac
  done
}

confirm_disk_erase() {
  local disk="$1"
  local typed

  echo "Type the full disk path to confirm erase: $disk"
  read -r -p "> " typed
  [[ "$typed" == "$disk" ]] || die "Confirmation mismatch. Aborting to protect data."
}

partition_path() {
  local disk="$1"
  local part_num="$2"

  # nvme0n1/mmcblk0 style devices need a 'p' separator.
  if [[ "$disk" =~ [0-9]$ ]]; then
    printf "%sp%s\n" "$disk" "$part_num"
  else
    printf "%s%s\n" "$disk" "$part_num"
  fi
}

require_commands() {
  local missing=()
  local cmd

  for cmd in "${REQUIRED_COMMANDS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  [[ ${#missing[@]} -eq 0 ]] || die "Missing required commands: ${missing[*]}"
}

assert_disk_not_mounted() {
  local disk="$1"

  [[ -b "$disk" ]] || die "Selected device is not a block device: $disk"

  local mounted_entries
  mounted_entries="$(lsblk -nrpo NAME,MOUNTPOINTS "$disk" | awk '$2 != ""')"
  [[ -z "$mounted_entries" ]] || die "Disk or partitions are mounted. Unmount before continuing:\n$mounted_entries"
}

parent_disk_from_source() {
  local src="$1"
  local type
  local pkname

  [[ "$src" == /dev/* ]] || return 0

  type="$(lsblk -no TYPE "$src" 2>/dev/null || true)"
  if [[ "$type" == "disk" ]]; then
    printf "%s\n" "$src"
    return 0
  fi

  pkname="$(lsblk -no PKNAME "$src" 2>/dev/null || true)"
  [[ -n "$pkname" ]] && printf "/dev/%s\n" "$pkname"
}

assert_not_live_media_disk() {
  local selected_disk="$1"
  local mount_path
  local src
  local parent

  # Protect current system/root and common Arch ISO boot media mount.
  for mount_path in / /run/archiso/bootmnt; do
    src="$(findmnt -n -o SOURCE "$mount_path" 2>/dev/null || true)"
    [[ -n "$src" ]] || continue
    parent="$(parent_disk_from_source "$src")"
    [[ -n "$parent" ]] || continue

    if [[ "$parent" == "$selected_disk" ]]; then
      die "Refusing to wipe active/live media disk: $selected_disk (in use by $mount_path via $src)"
    fi
  done
}

wait_for_partition() {
  local part="$1"
  local i

  for i in {1..20}; do
    [[ -b "$part" ]] && return 0
    sleep 0.5
  done

  die "Partition device did not appear: $part"
}

select_disk() {
  log "Available disks:"
  local -a disks=()
  local i=0
  
  # Parse lsblk to find top-level disks (MODEL can contain spaces, so keep TYPE
  # before MODEL to make awk field matching reliable).
  while IFS= read -r line; do
    disks+=("$line")
  done < <(lsblk -d -n -o NAME,SIZE,TYPE,MODEL | awk '$3=="disk" { $3=""; sub(/^ +/, ""); sub(/[[:space:]]+$/, ""); print }')
  
  if [[ ${#disks[@]} -eq 0 ]]; then
    die "No block devices found"
  fi
  
  # Display options
  for i in "${!disks[@]}"; do
    printf "  [%d] %s\n" "$((i + 1))" "${disks[$i]}"
  done
  
  local choice
  while true; do
    read -r -p "Select disk number (1-${#disks[@]}): " choice
    if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#disks[@]})); then
      SELECTED_DISK="/dev/$(echo "${disks[$((choice - 1))]}" | awk '{print $1}')"
      return 0
    fi
    echo "Invalid selection. Please enter a number between 1 and ${#disks[@]}"
  done
}

get_efi_size() {
  log "EFI Partition Size Options:"
  for i in "${!EFI_OPTIONS[@]}"; do
    local size=${EFI_OPTIONS[$i]}
    local marker=""
    [[ $size -eq $EFI_DEFAULT ]] && marker=" (recommended)"
    printf "  [%d] %d MiB%s\n" "$((i + 1))" "$size" "$marker"
  done
  
  local choice
  while true; do
    read -r -p "Select EFI size (1-${#EFI_OPTIONS[@]}) [default: 2]: " choice
    choice="${choice:-2}"
    if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#EFI_OPTIONS[@]})); then
      EFI_SIZE_MIB=${EFI_OPTIONS[$((choice - 1))]}
      return 0
    fi
    echo "Invalid selection."
  done
}

show_partition_plan() {
  local disk="$1"
  local efi_size="$2"
  local efi_part
  local btrfs_part
  efi_part="$(partition_path "$disk" 1)"
  btrfs_part="$(partition_path "$disk" 2)"
  
  log "=== Partition Plan ==="
  printf "Disk: %s\n" "$disk"
  printf "Partition 1: %d MiB FAT32 (EFI)\n" "$efi_size"
  printf "Partition 2: Btrfs (remaining space)\n"
  printf "Expected paths: %s (EFI), %s (Btrfs)\n" "$efi_part" "$btrfs_part"
  printf "\nBtrfs Subvolumes to create:\n"
  for sv in "${SUBVOLS[@]}"; do
    printf "  - %s\n" "$sv"
  done
  printf "\nMount Points:\n"
  printf "  @ → /\n"
  printf "  @home → /home\n"
  printf "  @snapshots → /.snapshots\n"
  printf "  @log → /var/log\n"
  printf "  @pkg → /var/cache/pacman/pkg\n"
}

# ============================================================================
# Partitioning Functions
# ============================================================================

partition_disk() {
  local disk="$1"
  local efi_size="$2"
  local efi_end_mib=$((1 + efi_size))
  local efi_part
  local btrfs_part
  efi_part="$(partition_path "$disk" 1)"
  btrfs_part="$(partition_path "$disk" 2)"
  
  log "Creating GPT partition table and partitions..."
  
  # Create GPT table and partitions
  # EFI: 1 MiB to (1 + efi_size) MiB so size is exactly efi_size MiB
  # Btrfs: starts immediately after EFI partition
  parted "$disk" --script \
    mklabel gpt \
    mkpart ESP fat32 1MiB "${efi_end_mib}MiB" \
    set 1 esp on \
    mkpart primary btrfs "${efi_end_mib}MiB" 100%

  partprobe "$disk" 2>/dev/null || true
  udevadm settle 2>/dev/null || true

  wait_for_partition "$efi_part"
  wait_for_partition "$btrfs_part"
  
  log "Verifying partitions..."
  [[ -b "$efi_part" ]] || die "Missing EFI partition: $efi_part"
  [[ -b "$btrfs_part" ]] || die "Missing Btrfs partition: $btrfs_part"
  
  log "Partitions created successfully"
}

format_filesystems() {
  local disk="$1"
  local efi_part
  local btrfs_part
  efi_part="$(partition_path "$disk" 1)"
  btrfs_part="$(partition_path "$disk" 2)"
  
  log "Formatting EFI partition: $efi_part"
  mkfs.fat -F32 "$efi_part" || die "Failed to format EFI partition"
  
  log "Formatting Btrfs partition: $btrfs_part"
  mkfs.btrfs -f "$btrfs_part" || die "Failed to format Btrfs partition"
  
  log "Verifying filesystems..."
  local blkid_output
  blkid_output=$(blkid "$efi_part" "$btrfs_part" 2>/dev/null) || die "Failed to verify filesystems"
  
  echo "$blkid_output"
}

# ============================================================================
# Subvolume Functions
# ============================================================================

create_subvolumes() {
  local disk="$1"
  local btrfs_part
  btrfs_part="$(partition_path "$disk" 2)"
  
  log "Creating Btrfs subvolumes..."
  
  # Create temp mount point
  mkdir -p "$MNT_TEMP"
  mount "$btrfs_part" "$MNT_TEMP"
  
  # Create subvolumes
  for sv in "${SUBVOLS[@]}"; do
    log "  Creating subvolume: $sv"
    btrfs subvolume create "$MNT_TEMP/$sv" || die "Failed to create subvolume $sv"
  done
  
  log "Verifying subvolume creation..."
  btrfs subvolume list "$MNT_TEMP" || die "Failed to list subvolumes"
  
  umount "$MNT_TEMP"
  log "Subvolumes created successfully"
}

# ============================================================================
# Verification Functions
# ============================================================================

verify_setup() {
  local disk="$1"
  local btrfs_part
  btrfs_part="$(partition_path "$disk" 2)"
  
  log "=== Temporary mount verification ==="
  mkdir -p "$MNT_TEMP"
  
  log "Testing Btrfs subvolume mounts..."
  
  # Mount root subvolume
  mount -o subvol=@,noatime,compress=zstd:3 "$btrfs_part" "$MNT_TEMP" || \
    die "Failed to mount root subvolume"

  # Create mount points inside the mounted root subvolume.
  mkdir -p "$MNT_TEMP/home" \
    "$MNT_TEMP/.snapshots" \
    "$MNT_TEMP/var/log" \
    "$MNT_TEMP/var/cache/pacman/pkg"
  
  # Mount remaining subvolumes
  mount -o subvol=@home,noatime,compress=zstd:3 "$btrfs_part" "$MNT_TEMP/home" || \
    die "Failed to mount @home"
  
  mount -o subvol=@snapshots,noatime,compress=zstd:3 "$btrfs_part" "$MNT_TEMP/.snapshots" || \
    die "Failed to mount @snapshots"
  
  mount -o subvol=@log,noatime,compress=zstd:3 "$btrfs_part" "$MNT_TEMP/var/log" || \
    die "Failed to mount @log"
  
  mount -o subvol=@pkg,noatime,compress=zstd:3 "$btrfs_part" "$MNT_TEMP/var/cache/pacman/pkg" || \
    die "Failed to mount @pkg"
  
  log "All subvolume mounts successful"
}

print_final_report() {
  local disk="$1"
  local efi_part
  local btrfs_part
  local sv
  efi_part="$(partition_path "$disk" 1)"
  btrfs_part="$(partition_path "$disk" 2)"
  
  log "=== Final Verification Report ==="
  
  echo ""
  echo "=== Partition Table ==="
  parted "$disk" print
  
  echo ""
  echo "=== Filesystem Information ==="
  blkid "$efi_part" "$btrfs_part" 2>/dev/null || true
  
  echo ""
  echo "=== Btrfs Subvolumes ==="
  btrfs subvolume list "$MNT_TEMP" || true
  
  echo ""
  echo "=== Mount Test Results ==="
  mount | grep "$MNT_TEMP" || true
  
  echo ""
  echo "=== Success Summary ==="
  echo "Selected disk: $disk"
  echo "EFI size: ${EFI_SIZE_MIB} MiB"
  echo "EFI partition: $efi_part"
  echo "Btrfs partition: $btrfs_part"
  echo "Subvolumes created:"
  for sv in "${SUBVOLS[@]}"; do
    echo "  - $sv"
  done

  echo ""
  echo "=== Archinstall Handoff ==="
  echo "Disk preparation complete."
  echo ""
  echo "Next step:"
  echo "1. Run: archinstall"
  echo "2. Choose: Use existing partitions"
  echo "3. EFI partition: $efi_part mounted at /efi"
  echo "4. Btrfs partition: $btrfs_part mounted at /"
  echo "5. Profile: minimal"
  echo "6. Bootloader: systemd-boot"
  echo "7. Swap: none"
  echo "8. Do not repartition or reformat the disk"
  echo "9. Create your user and enable NetworkManager"
  echo "10. If archinstall does not preserve this subvolume layout, use the manual mounts below first"
  echo ""
  echo "The Btrfs subvolumes are already created:"
  echo "@, @home, @snapshots, @log, @pkg"
  echo "Do not recreate them."

  echo ""
  echo "=== Warning ==="
  echo "Use existing partitions only."
  echo "Do not repartition."
  echo "Do not reformat."

  echo ""
  echo "Optional manual mount commands before archinstall:"
  echo "mount -o subvol=@,noatime,compress=zstd:3 $btrfs_part /mnt"
  echo "mkdir -p /mnt/{home,.snapshots,var/log,var/cache/pacman/pkg,efi}"
  echo "mount -o subvol=@home,noatime,compress=zstd:3 $btrfs_part /mnt/home"
  echo "mount -o subvol=@snapshots,noatime,compress=zstd:3 $btrfs_part /mnt/.snapshots"
  echo "mount -o subvol=@log,noatime,compress=zstd:3 $btrfs_part /mnt/var/log"
  echo "mount -o subvol=@pkg,noatime,compress=zstd:3 $btrfs_part /mnt/var/cache/pacman/pkg"
  echo "mount $efi_part /mnt/efi"
}

# ============================================================================
# Main Flow
# ============================================================================

main() {
  log "=== Arch Linux Hard Drive Formatter ==="
  log "This script will ERASE the selected disk!"
  echo ""
  
  require_root
  require_commands
  
  # Phase 1: Pre-flight checks and user input
  log "Phase 1: Pre-flight Checks"
  select_disk
  assert_disk_not_mounted "$SELECTED_DISK"
  assert_not_live_media_disk "$SELECTED_DISK"
  log "Selected disk: $SELECTED_DISK"
  echo ""

  confirm_disk_erase "$SELECTED_DISK"
  echo ""
  
  get_efi_size
  log "Selected EFI size: $EFI_SIZE_MIB MiB"
  echo ""
  
  show_partition_plan "$SELECTED_DISK" "$EFI_SIZE_MIB"
  echo ""
  
  if ! confirm "Proceed with partitioning?"; then
    die "Aborted by user"
  fi
  echo ""
  
  # Phase 2: Partitioning
  log "Phase 2: Partitioning"
  partition_disk "$SELECTED_DISK" "$EFI_SIZE_MIB"
  echo ""
  
  # Phase 3: Formatting
  log "Phase 3: Formatting Filesystems"
  format_filesystems "$SELECTED_DISK"
  echo ""
  
  # Phase 4: Subvolume Creation
  log "Phase 4: Creating Btrfs Subvolumes"
  create_subvolumes "$SELECTED_DISK"
  echo ""
  
  # Phase 5: Verification
  log "Phase 5: Temporary mount verification"
  verify_setup "$SELECTED_DISK"
  echo ""
  
  # Phase 6: Final Report
  log "Phase 6: Final Report"
  print_final_report "$SELECTED_DISK"
  echo ""
  
  if confirm "Setup complete! Does everything look correct?"; then
    log "✓ SUCCESS: Your drive is ready for Arch installation!"
    log "Follow the Archinstall handoff block above and start archinstall now."
  else
    die "User rejected final verification"
  fi
}

main "$@"
