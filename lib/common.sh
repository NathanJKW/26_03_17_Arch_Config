#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf '\n[ERROR] %s\n' "$*" >&2
  exit 1
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this script as root"
}

require_arch() {
  command -v pacman >/dev/null 2>&1 || die "This script is for Arch-based systems"
}

require_config() {
  local missing=()
  local name
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || missing+=("$name")
  done
  [[ ${#missing[@]} -eq 0 ]] || die "Missing config values: ${missing[*]}"
}

package_installed() {
  pacman -Q "$1" >/dev/null 2>&1
}

install_pacman() {
  local pkgs=()
  local pkg
  for pkg in "$@"; do
    package_installed "$pkg" || pkgs+=("$pkg")
  done

  if [[ ${#pkgs[@]} -gt 0 ]]; then
    pacman -S --needed --noconfirm "${pkgs[@]}"
  fi
}

ensure_line() {
  local line="$1"
  local file="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -Fqx "$line" "$file" || echo "$line" >> "$file"
}

enable_service() {
  local service="$1"
  systemctl enable "$service"
}

user_exists() {
  id "$1" >/dev/null 2>&1
}

ensure_user_in_group() {
  local user="$1"
  local group="$2"
  id -nG "$user" | tr ' ' '\n' | grep -qx "$group" || usermod -aG "$group" "$user"
}

copy_if_missing() {
  local src="$1"
  local dest="$2"
  [[ -e "$dest" ]] || install -Dm644 "$src" "$dest"
}
