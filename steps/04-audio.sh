#!/usr/bin/env bash
set -euo pipefail

install_pacman \
  pipewire wireplumber \
  pipewire-alsa pipewire-pulse pipewire-jack \
  pavucontrol pamixer playerctl
