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
    read -p "$prompt (Y/n): " response
    response="${response:-Y}"
    case "$response" in
      [Yy]) return 0 ;;
      [Nn]) return 1 ;;
      *) echo "Please answer Y or N" ;;
    esac
  done
}

select_disk() {
  log "Available disks:"
  local -a disks=()
  local i=0
  
  # Parse lsblk to find block devices (skip partitions)
  while IFS= read -r line; do
    disks+=("$line")
  done < <(lsblk -d -n -o NAME,SIZE,MODEL | grep -v "^loop")
  
  if [[ ${#disks[@]} -eq 0 ]]; then
    die "No block devices found"
  fi
  
  # Display options
  for i in "${!disks[@]}"; do
    printf "  [%d] %s\n" "$((i + 1))" "${disks[$i]}"
  done
  
  local choice
  while true; do
    read -p "Select disk number (1-${#disks[@]}): " choice
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
    read -p "Select EFI size (1-${#EFI_OPTIONS[@]}) [default: 2]: " choice
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
  local btrfs_start=$((efi_size + 1))
  
  log "=== Partition Plan ==="
  printf "Disk: %s\n" "$disk"
  printf "Partition 1: %d MiB FAT32 (EFI)\n" "$efi_size"
  printf "Partition 2: Btrfs (remaining space)\n"
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
  
  log "Creating GPT partition table and partitions..."
  
  # Create GPT table and partitions
  # EFI: 1 MiB to (efi_size) MiB
  # Btrfs: (efi_size+1) MiB to end
  parted "$disk" --script \
    mklabel gpt \
    mkpart ESP fat32 1MiB "${efi_size}MiB" \
    set 1 esp on \
    mkpart primary btrfs "${efi_size}MiB" 100%
  
  # Give kernel time to register partitions
  sleep 2
  
  log "Verifying partitions..."
  if ! lsblk "$disk" -o NAME,TYPE,SIZE | grep -q part; then
    die "Failed to create partitions on $disk"
  fi
  
  log "Partitions created successfully"
}

format_filesystems() {
  local disk="$1"
  local efi_part="${disk}p1"
  local btrfs_part="${disk}p2"
  
  # Handle NVMe naming (e.g., /dev/nvme0n1 → /dev/nvme0n1p1)
  if [[ $disk == *"nvme"* ]]; then
    efi_part="${disk}p1"
    btrfs_part="${disk}p2"
  fi
  
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
  local btrfs_part="${disk}p2"
  
  # Handle NVMe naming
  if [[ $disk == *"nvme"* ]]; then
    btrfs_part="${disk}p2"
  fi
  
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
  local btrfs_part="${disk}p2"
  
  # Handle NVMe naming
  if [[ $disk == *"nvme"* ]]; then
    btrfs_part="${disk}p2"
  fi
  
  log "=== Verification Phase ==="
  
  # Create temp directories for mount test
  mkdir -p "$MNT_TEMP"/{home,.snapshots,var/log,var/cache/pacman/pkg}
  
  log "Testing Btrfs subvolume mounts..."
  
  # Mount root subvolume
  mount -o subvol=@,noatime,compress=zstd:3 "$btrfs_part" "$MNT_TEMP" || \
    die "Failed to mount root subvolume"
  
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
  local efi_part="${disk}p1"
  local btrfs_part="${disk}p2"
  
  # Handle NVMe naming
  if [[ $disk == *"nvme"* ]]; then
    efi_part="${disk}p1"
    btrfs_part="${disk}p2"
  fi
  
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
  echo "All verifications passed!"
}

# ============================================================================
# Main Flow
# ============================================================================

main() {
  log "=== Arch Linux Hard Drive Formatter ==="
  log "This script will ERASE the selected disk!"
  echo ""
  
  require_root
  
  # Phase 1: Pre-flight checks and user input
  log "Phase 1: Pre-flight Checks"
  select_disk
  log "Selected disk: $SELECTED_DISK"
  echo ""
  
  if ! confirm "WARNING: This will ERASE $SELECTED_DISK. Continue?"; then
    die "Aborted by user"
  fi
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
  log "Phase 5: Verification & Mount Testing"
  verify_setup "$SELECTED_DISK"
  echo ""
  
  # Phase 6: Final Report
  log "Phase 6: Final Report"
  print_final_report "$SELECTED_DISK"
  echo ""
  
  if confirm "Setup complete! Does everything look correct?"; then
    log "✓ SUCCESS: Your drive is ready for Arch installation!"
    log "Next step: Run 01-base.sh to continue installation"
  else
    die "User rejected final verification"
  fi
}

main "$@"
