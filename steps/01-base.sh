#!/usr/bin/env bash
set -euo pipefail

install_pacman \
  base-devel git curl wget unzip zip man-db man-pages \
  networkmanager openssh reflector rsync \
  neovim nano sudo bash-completion \
  zsh tmux htop btop fastfetch \
  xdg-user-dirs xdg-utils

enable_service NetworkManager

[[ -n "${HOSTNAME:-}" ]] && echo "$HOSTNAME" > /etc/hostname
[[ -n "${TIMEZONE:-}" ]] && ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime

if [[ -n "${LOCALE:-}" ]]; then
  sed -i "s/^#\(${LOCALE} .*\)/\1/" /etc/locale.gen || true
  locale-gen
  printf 'LANG=%s\n' "$LOCALE" > /etc/locale.conf
fi

[[ -n "${KEYMAP:-}" ]] && printf 'KEYMAP=%s\n' "$KEYMAP" > /etc/vconsole.conf
