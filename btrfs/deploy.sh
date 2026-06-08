#!/bin/sh
set -e # Остановить выполнение, если какая-то команда завершится ошибкой

echo "=== Шаг 1: Монтирование корня и подготовка сабволюмов ==="
mount -o subvol=/ /dev/nvme0n1p3 /mnt

btrfs subvolume snapshot /mnt /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/.snapshots

echo "=== Шаг 2: Перенос данных /home ==="
cp -a /mnt/home/. /mnt/@home/

echo "=== Шаг 3: Очистка старого корня ==="
cd /mnt
rm -rf bin boot dev etc home lib lib64 media mnt opt proc root sbin srv sys tmp usr var

cd ~
umount /mnt

echo "=== Шаг 4: Монтирование новой структуры ==="
mount -o subvol=@,noatime,compress=zstd:1,ssd /dev/nvme0n1p3 /mnt

mkdir -p /mnt/home /mnt/.snapshots /mnt/boot/efi

mount -o subvol=@home,noatime,compress=zstd:1,ssd /dev/nvme0n1p3 /mnt/home
mount /dev/nvme0n1p1 /mnt/boot/efi

echo "=== Шаг 5: Обновление менеджера пакетов Void ==="
# --yes автоматически соглашается на установку
xbps-install -u xbps --yes
xbps-install -S --yes

echo "=== Шаг 6: Запись конфигурации fstab ==="
# Используем хередок (cat << 'EOF'), чтобы безопасно записать многострочный текст
cat << 'EOF' > /mnt/etc/fstab
UUID=4d4d1973-02bf-4220-83d4-f7c570937b79    /    btrfs rw,noatime,compress=zstd:1,ssd,subvol=@ 0 0
UUID=4d4d1973-02bf-4220-83d4-f7c570937b79    /home    btrfs rw,noatime,compress=zstd:1,ssd,subvol=@home 0 0
UUID=4A64-8B5A    /boot/efi    vfat rw,noatime,fmask=0077,dmask=0077 0 2
EOF

echo "=== Шаг 7: Проверка монтирования и обновление загрузчика ==="
mount -a

# Если вы выполняете это из live-режима, grub нужно ставить внутри chroot.
# Но так как у вас в командах chroot нет, запускаем напрямую, как вы просили:
grub-install /dev/nvme0n1
update-grub

echo "=== Скрипт успешно завершил работу! ==="
