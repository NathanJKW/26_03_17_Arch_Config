#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/install.log"

exec > >(tee -a "$LOG_FILE") 2>&1

# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.conf"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

log "Starting Arch post-install"

require_root
require_arch
require_config USERNAME HOSTNAME GPU

export SCRIPT_DIR USERNAME HOSTNAME GPU TIMEZONE LOCALE KEYMAP INSTALL_BLUETOOTH INSTALL_SDDM AUR_HELPER

for step in "$SCRIPT_DIR"/steps/*.sh; do
  log "Running $(basename "$step")"
  # shellcheck disable=SC1090
  source "$step"
done

log "Complete"
