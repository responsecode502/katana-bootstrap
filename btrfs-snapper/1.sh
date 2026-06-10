#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    exit 1
fi

ROOT_PARTITION="/dev/nvme0n1p3"
BTRFS_ROOT="/mnt/btrfs-root"

xbps-install -u xbps --yes
xbps-install -S snapper dbus dcron grub-btrfs --yes
sudo ln -s /etc/sv/dbus /var/service/
sudo ln -s /etc/sv/dcron /var/service/

sleep 5

mkdir -p "$BTRFS_ROOT"
mount "$ROOT_PARTITION" "$BTRFS_ROOT"
btrfs subvolume create "$BTRFS_ROOT/@.snapshots"
umount "$BTRFS_ROOT"
rm -rf /.snapshots
snapper -c root create-config /
snapper -c root create -d "Pure system"

grub-mkconfig -o /boot/grub/grub.cfg
update-grub