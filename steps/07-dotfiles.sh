#!/usr/bin/env bash
set -euo pipefail

sudo -u "$USERNAME" xdg-user-dirs-update || true

BASHRC="/home/$USERNAME/.bashrc"
ensure_line 'if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then exec Hyprland; fi' "$BASHRC"

chown "$USERNAME:$USERNAME" "$BASHRC"
