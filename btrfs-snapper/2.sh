#!/usr/bin/env bash
set -euo pipefail

# 1. Защита от sudo (работает корректно)
if [ "$(id -u)" -ne 0 ]; then
    echo "Ошибка: Запустите скрипт от имени root (через sudo)" >&2
    exit 1
fi

echo "[1] Переустановка точки монтирования для Snapper..."
# Отмонтируем сабвуфер снимков, если он вдруг примонтирован
umount -l /.snapshots 2>/dev/null || true

# Snapper НЕ примет существующую папку. Удаляем только саму ТOЧКУ монтирования.
# Сам сабвуфер @/.snapshots на диске никуда не денется, мы его временно отцепили.
rm -rf /.snapshots

echo "[2] Установка пакетов и активация сервисов..."
xbps-install -S snapper dcron grub-btrfs --yes
ln -sf /etc/sv/dcron /var/service/
ln -sf /etc/sv/dbus /var/service/

echo "[3] Инициализация конфигурации Snapper..."
# Snapper создает свою чистую стандартную папку /.snapshots
snapper -c root create-config /

# Удаляем пустую папку, созданную снаппером, чтобы вернуть наш сабвуфер
rmdir /.snapshots

# Пересоздаем чистую точку монтирования
mkdir /.snapshots

echo "[4] Монтируем сабвуфер снимков обратно..."
# mount -a подтянет настройки из fstab, где прописан subvol=@/.snapshots
mount -a
chmod 750 /.snapshots

echo "[5] Создание первого снимка и обновление GRUB..."
# Создаем первый снимок чистой системы
snapper -c root create -d "Pure system"

# Обновляем конфиг GRUB, чтобы grub-btrfs подтянул созданный снимок
grub-mkconfig -o /boot/grub/grub.cfg

echo "Второй этап настройки успешно завершен!"
