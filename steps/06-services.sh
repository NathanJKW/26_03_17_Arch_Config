#!/usr/bin/env bash
set -euo pipefail

if [[ "${INSTALL_BLUETOOTH:-true}" == "true" ]]; then
  install_pacman bluez bluez-utils blueman
  enable_service bluetooth
fi

if [[ "${INSTALL_SDDM:-false}" == "true" ]]; then
  install_pacman sddm
  enable_service sddm
fi
