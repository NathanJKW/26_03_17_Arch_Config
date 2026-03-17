# Arch + Hyprland post-install starter

A small, rerunnable Bash-based setup you can keep in a Git repo and run after `archinstall`.

## Usage

1. Edit `config.conf`
2. Run:

```bash
sudo bash install.sh
```

## Notes

- This is intended for the post-install stage only.
- Partitioning, bootloader setup, and early install remain manual or handled by `archinstall`.
- For NVIDIA, you may want additional Hyprland environment tweaks depending on your driver version.
