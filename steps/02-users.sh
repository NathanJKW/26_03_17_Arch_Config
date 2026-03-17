#!/usr/bin/env bash
set -euo pipefail

if ! user_exists "$USERNAME"; then
  useradd -m -G wheel -s /bin/bash "$USERNAME"
  passwd "$USERNAME"
fi

ensure_user_in_group "$USERNAME" wheel
install -d /etc/sudoers.d
cat > /etc/sudoers.d/10-wheel <<'SUDOEOF'
%wheel ALL=(ALL:ALL) ALL
SUDOEOF
chmod 440 /etc/sudoers.d/10-wheel

if [[ "${AUR_HELPER:-yay}" == "yay" ]] && ! command -v yay >/dev/null 2>&1; then
  sudo -u "$USERNAME" bash <<'USEREOF'
set -euo pipefail
cd "$HOME"
if [[ ! -d yay ]]; then
  git clone https://aur.archlinux.org/yay.git
fi
cd yay
makepkg -si --noconfirm
USEREOF
fi
