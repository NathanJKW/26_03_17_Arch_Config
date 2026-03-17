#!/usr/bin/env bash
set -euo pipefail

case "$GPU" in
  amd)
    install_pacman mesa vulkan-radeon libva-mesa-driver xf86-video-amdgpu
    ;;
  nvidia)
    install_pacman nvidia nvidia-utils nvidia-settings libva-nvidia-driver
    ensure_line 'options nvidia_drm modeset=1' /etc/modprobe.d/nvidia.conf
    ;;
  intel)
    install_pacman mesa vulkan-intel intel-media-driver
    ;;
  vm)
    install_pacman mesa
    ;;
  *)
    die "Unsupported GPU type: $GPU"
    ;;
esac
