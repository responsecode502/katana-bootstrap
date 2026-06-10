#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root" >&2; exit 1
fi

echo "=== Installing packages and enabling services ==="
xbps-install -S snapper dcron grub-btrfs --yes
ln -sf /etc/sv/dcron /var/service/
ln -sf /etc/sv/dbus /var/service/

echo "=== Initializing Snapper ==="
# Unmount and clear the path to prevent Snapper initialization errors
umount /.snapshots 2>/dev/null || true
rm -rf /.snapshots

# Generate config (this automatically recreates a dummy /.snapshots)
snapper -c root create-config /

# Swap Snapper's dummy folder for our real Btrfs subvolume
rmdir /.snapshots
mkdir /.snapshots
mount -a
chmod 750 /.snapshots

echo "=== Creating initial snapshot and updating GRUB ==="
snapper -c root create -d "Pure system"
grub-mkconfig -o /boot/grub/grub.cfg

echo "=== Done! ==="
