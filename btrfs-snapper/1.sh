#!/usr/bin/env bash
# Move root check to the very top, before set -e
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

set -euo pipefail

ROOT_PARTITION="/dev/nvme0n1p3"
BOOT_EFI_PARTITION="/dev/nvme0n1p1"

echo "[1] creating subvolumes"
mount -o subvol=/ "$ROOT_PARTITION" /mnt

# Clean up existing subvolumes to prevent errors
btrfs subvolume delete /mnt/@home || true
btrfs subvolume delete /mnt/@ || true

# Snapshot and create subvolumes
btrfs subvolume snapshot /mnt /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@/.snapshots

echo "[2] copying home files"
# Use /mnt/@/home as the source to ensure we grab the home files before moving mount
cp -a /mnt/@/home/. /mnt/@home/

echo "[3] cleaning unused /mnt core files"
# Securely remove /home content from the snapshot while keeping /home directory
find /mnt/@/home -mindepth 1 -delete

echo "[4] unmounting /mnt"
cd /
umount /mnt

# Определяем UUID корневого и /boot/efi разделов.
UUID_BTRFS=$(blkid -s UUID -o value "$ROOT_PARTITION")
UUID_EFI=$(blkid -s UUID -o value "$BOOT_EFI_PARTITION")

echo "[5] UUID for BTRFS: $UUID_BTRFS"
echo "UUID for EFI: $UUID_EFI"

echo "[6] mounting subvolumes, creating needed dirs"
# Mount root subvolume
mount -o subvol=@,noatime,compress=zstd:1,ssd "$ROOT_PARTITION" /mnt
mkdir -p /mnt/home /mnt/boot/efi /mnt/.snapshots
# Mount home and snapshots
mount -o subvol=@home,noatime,compress=zstd:1,ssd "$ROOT_PARTITION" /mnt/home
mount -o subvol=@/.snapshots,noatime,compress=zstd:1,ssd "$ROOT_PARTITION" /mnt/.snapshots
# Mount EFI
mount "$BOOT_EFI_PARTITION" /mnt/boot/efi

echo "[7] configuring fstab"
cat << EOF > /mnt/etc/fstab
UUID=$UUID_BTRFS    /            btrfs    rw,noatime,compress=zstd:1,ssd,subvol=@        0 0
UUID=$UUID_BTRFS    /home        btrfs    rw,noatime,compress=zstd:1,ssd,subvol=@home    0 0
UUID=$UUID_BTRFS    /.snapshots  btrfs    rw,noatime,compress=zstd:1,ssd,subvol=@/.snapshots 0 0
UUID=$UUID_EFI      /boot/efi    vfat     rw,noatime,fmask=0077,dmask=0077               0 2
EOF

echo "[8] creating temporary links inside RAM"
for dir in dev proc sys run; do
    mount --bind /$dir /mnt/$dir
done

# EFIVARS_DIR="/sys/firmware/efi/efivars"
# mount --bind "$EFIVARS_DIR" "/mnt$EFIVARS_DIR"

echo "[9] chroot configurations"
chroot /mnt /bin/bash << 'CHROOT_EOF'
# Setup GRUB for BTRFS
if ! grep -q "GRUB_BTRFS_SUBVOLROOT=@" /etc/default/grub; then
    echo "GRUB_BTRFS_SUBVOLROOT=@" >> /etc/default/grub
fi
sed -i 's/GRUB_DISABLE_OS_PROBER=true/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=void \
    --recheck

grub-mkconfig -o /boot/grub/grub.cfg
CHROOT_EOF

echo "Done. Please unmount manually: umount -R /mnt"
