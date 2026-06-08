#!/bin/sh
set -e # Остановить выполнение, если какая-то команда завершится ошибкой

echo "=== 1 - host and subvols ==="
mount -o subvol=/ /dev/nvme0n1p3 /mnt

btrfs subvolume snapshot /mnt /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/.snapshots

echo "=== 2 - home transfer ==="
cp -a /mnt/home/. /mnt/@home/

echo "=== 3 - old home cleanup ==="
cd /mnt
rm -rf bin boot dev etc home lib lib64 media mnt opt proc root sbin srv sys tmp usr var

cd ~
umount /mnt

UUID_BTRFS=$(blkid -s UUID -o value /dev/nvme0n1p3)
UUID_EFI=$(blkid -s UUID -o value /dev/nvme0n1p1)

echo "=== 4 - new structure mount ==="
mount -o subvol=@,noatime,compress=zstd:1,ssd /dev/nvme0n1p3 /mnt

mkdir -p /mnt/home /mnt/.snapshots /mnt/boot/efi

mount -o subvol=@home,noatime,compress=zstd:1,ssd /dev/nvme0n1p3 /mnt/home
mount /dev/nvme0n1p1 /mnt/boot/efi

echo "=== 5 xbps update  ==="
# --yes автоматически соглашается на установку
xbps-install -u xbps --yes
xbps-install -S --yes

echo "=== 6 - fstab ==="
# Используем хередок (cat << 'EOF'), чтобы безопасно записать многострочный текст
cat << 'EOF' > /mnt/etc/fstab
UUID=$UUID_BTRFS    /            btrfs    rw,noatime,compress=zstd:1,ssd,subvol=@        0 0
UUID=$UUID_BTRFS    /home        btrfs    rw,noatime,compress=zstd:1,ssd,subvol=@home    0 0
UUID=$UUID_EFI      /boot/efi    vfat     rw,noatime,fmask=0077,dmask=0077               0 2
EOF

echo "=== 7 - mounts, dirs, chroot ==="

for dir in dev proc sys run; do
    mount --mkdir --bind /$dir /mnt/$dir
done

mount --mkdir --bind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars

mount -a

chroot /mnt /bin/bash << 'CHROOT_EOF'
echo "GRUB_BTRFS_SUBVOLROOT=@" >> /etc/default/grub
echo "GRUB_DISABLE_OS_PROBEL=false" >> /etc/default/grub
grub-install /dev/nvme0n1
exit
CHROOT_EOF

echo "=== Script end ==="
