#!/usr/bin/env bash
set -euo pipefail

ROOT_PARTITION="/dev/nvme0n1p3"
BOOT_EFI_PARTITION="/dev/nvme0n1p1"

echo "[1] creating subvolumes"
# Монтируем устройство в /mnt, используем главный subvolume.
mount -o subvol=/ "$ROOT_PARTITION" /mnt

# Копирование системных файлов void в @ subvolume.
btrfs subvolume snapshot /mnt /mnt/@

# Создание пустого subvolume @home и .snapshots соотв.
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/.snapshots

echo "[2] copying home files"
# Копирование файлов из home в соотв. subvolume.
cp -a /mnt/home/. /mnt/@home/

echo "[3] cleaning unused /mnt core files"
# Удаляем "болтающиеся" системные файлы.
cd /mnt
rm -rf bin boot dev etc home lib lib64 media mnt opt proc root sbin srv sys tmp usr var

echo "[4] unmounting /mnt"
# Переходим в корень live системы, размонт. ssd.
cd /
umount /mnt

# Определяем UUID корневого и /boot/efi разделов.
UUID_BTRFS=$(blkid -s UUID -o value "$ROOT_PARTITION")
UUID_EFI=$(blkid -s UUID -o value "$BOOT_EFI_PARTITION")

echo "[5] UUID for BTRFS: $UUID_BTRFS"
echo "UUID for EFI: $UUID_EFI"

echo "[6] mounting subvolumes, creating needed dirs"
# Теперь /mnt ссылается на @ subvolume.
mount -o subvol=@,noatime,compress=zstd:1,ssd "$ROOT_PARTITION" /mnt
mkdir -p /mnt/home /mnt/.snapshots /mnt/boot/efi
mount -o subvol=@home,noatime,compress=zstd:1,ssd "$ROOT_PARTITION" /mnt/home
mount "$BOOT_EFI_PARTITION" /mnt/boot/efi

#echo "[7] updating xbps"
#xbps-install -Su --yes

echo "[7] configuring fstab"
# Накатываем линковку под subvolumes.
cat << EOF > /mnt/etc/fstab
UUID=$UUID_BTRFS    /            btrfs    rw,noatime,compress=zstd:1,ssd,subvol=@        0 0
UUID=$UUID_BTRFS    /home        btrfs    rw,noatime,compress=zstd:1,ssd,subvol=@home    0 0
UUID=$UUID_BTRFS    /.snapshots  btrfs    rw,noatime,compress=zstd:1,ssd,subvol=.snapshots 0 0
UUID=$UUID_EFI      /boot/efi    vfat     rw,noatime,fmask=0077,dmask=0077               0 2
EOF

echo "[8] creating temporary links inside RAM"
# Ссылки в RAM, чтоб /mnt/$dir ссылался на папку live системы.
for dir in dev proc sys run; do
    mount --mkdir --bind /$dir /mnt/$dir
done

# Рабочие UEFI данные пробрасываем из live системы.
EFIVARS_DIR="/sys/firmware/efi/efivars"
mount --mkdir --bind "$EFIVARS_DIR" "/mnt$EFIVARS_DIR"

echo "[9] chroot configurations"
# Выполняем команды внутри chroot
chroot /mnt /bin/bash << 'CHROOT_EOF'
# Настройка GRUB для BTRFS
echo "GRUB_BTRFS_SUBVOLROOT=@" >> /etc/default/grub
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub 

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=void \
    --recheck

# Cоздаем актуальное меню загрузки GRUB с новыми путями к ядру
grub-mkconfig -o /boot/grub/grub.cfg

exit
CHROOT_EOF
