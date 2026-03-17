#!/usr/bin/env bash
set -euo pipefail

install_pacman \
  hyprland xdg-desktop-portal-hyprland \
  waybar rofi-wayland kitty dunst \
  wl-clipboard cliphist \
  grim slurp swappy \
  polkit-kde-agent qt5-wayland qt6-wayland \
  thunar thunar-archive-plugin file-roller \
  firefox noto-fonts noto-fonts-emoji ttf-dejavu ttf-liberation

install -d -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.config"

copy_if_missing "$SCRIPT_DIR/dotfiles/hypr/hyprland.conf" "/home/$USERNAME/.config/hypr/hyprland.conf"
copy_if_missing "$SCRIPT_DIR/dotfiles/waybar/config.jsonc" "/home/$USERNAME/.config/waybar/config.jsonc"
copy_if_missing "$SCRIPT_DIR/dotfiles/waybar/style.css" "/home/$USERNAME/.config/waybar/style.css"
copy_if_missing "$SCRIPT_DIR/dotfiles/kitty/kitty.conf" "/home/$USERNAME/.config/kitty/kitty.conf"

chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.config"
mkdir -p "/home/$USERNAME/.config/autostart"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.config/autostart"
