#!/usr/bin/env bash
set -euo pipefail

# Перенос снэпшотов в бэкап-папку.
umount /.snapshots || true
mv /.snapshots /.snapshots-backup

# Установка пакетов, запуск сервисов
xbps-install -S snapper dcron grub-btrfs --yes
ln -sf /etc/sv/dcron /var/service/
ln -sf /etc/sv/dbus /var/service/

snapper -c root create-config /
rmdir /.snapshots
mv /.snapshots-backup /.snapshots
mount -a
snapper -c root create -d "Pure system"
grub-mkconfig -o /boot/grub/grub.cfg