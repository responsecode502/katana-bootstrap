#!/usr/bin/env bash
# ==============================================================================
# Script for migrating Void Linux to Btrfs subvolumes (@, @home, @.snapshots)
# ==============================================================================
set -euo pipefail

# Root privileges check
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Target partitions configuration
ROOT_PARTITION="/dev/nvme0n1p3"
BOOT_EFI_PARTITION="/dev/nvme0n1p1"
TMP_MOUNT="/tmp/void_migration_root"

echo "=== Creating Btrfs subvolumes ==="
mkdir -p "$TMP_MOUNT"
# Mount partition root (subvol=/) to a temporary directory
mount -o subvol=/ "$ROOT_PARTITION" "$TMP_MOUNT"

# Create clean, isolated top-level subvolumes
btrfs subvolume create "$TMP_MOUNT/@"
btrfs subvolume create "$TMP_MOUNT/@home"
btrfs subvolume create "$TMP_MOUNT/@.snapshots"

echo "=== Moving system and user files ==="
# Safely copy system root to @ subvolume (excluding home and new subvolumes)
find "$TMP_MOUNT" -maxdepth 1 ! -name '@*' ! -name 'home' ! -name 'tmp' ! -name '.' -exec cp -a {} "$TMP_MOUNT/@/" \;

# Move user data to @home subvolume
if [ -d "$TMP_MOUNT/home" ]; then
    cp -a "$TMP_MOUNT/home/." "$TMP_MOUNT/@home/"
fi

echo "=== Cleaning old root files ==="
# Delete old system files from root. New subvolumes (@*) are protected by find pattern
find "$TMP_MOUNT" -maxdepth 1 ! -name '@*' ! -name '.' -exec rm -rf {} +

echo "=== Unmounting temporary root ==="
umount "$TMP_MOUNT"
rmdir "$TMP_MOUNT"

# Get partition UUIDs for fstab and bootloader
UUID_BTRFS=$(blkid -s UUID -o value "$ROOT_PARTITION")
UUID_EFI=$(blkid -s UUID -o value "$BOOT_EFI_PARTITION")

echo "[+] UUID for BTRFS: $UUID_BTRFS"
echo "[+] UUID for EFI: $UUID_EFI"

echo "=== Mounting new subvolumes into /mnt ==="
# Mount the main system subvolume @ to working directory /mnt
mount -o subvol=@,noatime,compress=zstd:1,ssd "$ROOT_PARTITION" /mnt

# Create required mount points inside the new system
mkdir -p /mnt/home /mnt/boot/efi /mnt/.snapshots

# Mount remaining subvolumes and EFI partition
mount -o subvol=@home,noatime,compress=zstd:1,ssd "$ROOT_PARTITION" /mnt/home
mount -o subvol=@.snapshots,noatime,compress=zstd:1,ssd "$ROOT_PARTITION" /mnt/.snapshots
mount "$BOOT_EFI_PARTITION" /mnt/boot/efi

echo "=== Configuring fstab ==="
# Generate proper mount table layout using subvolumes
cat << EOF > /mnt/etc/fstab
UUID=$UUID_BTRFS    /            btrfs    rw,noatime,compress=zstd:1,ssd,subvol=@        0 0
UUID=$UUID_BTRFS    /home        btrfs    rw,noatime,compress=zstd:1,ssd,subvol=@home    0 0
UUID=$UUID_BTRFS    /.snapshots  btrfs    rw,noatime,compress=zstd:1,ssd,subvol=@.snapshots 0 0
UUID=$UUID_EFI      /boot/efi    vfat     rw,noatime,fmask=0077,dmask=0077               0 2
EOF

echo "=== Mounting virtual file systems for chroot ==="
# Bind API filesystems from the live environment
for dir in dev proc sys run; do
    mount --mkdir --bind /$dir /mnt/$dir
done

# Bind EFI variables for proper grub-install execution
EFIVARS_DIR="/sys/firmware/efi/efivars"
if [ -d "$EFIVARS_DIR" ]; then
    mount --mkdir --bind "$EFIVARS_DIR" "/mnt$EFIVARS_DIR"
fi

echo "=== Configuring environment inside chroot ==="
# Run GRUB configuration commands within the target system context
chroot /mnt /bin/bash << 'CHROOT_EOF'
set -euo pipefail

# Configure GRUB to handle root on a Btrfs subvolume properly
# Remove old records if they exist to prevent duplication
sed -i '/GRUB_BTRFS_SUBVOLROOT/d' /etc/default/grub
sed -i '/GRUB_DISABLE_OS_PROBER/d' /etc/default/grub

echo "GRUB_BTRFS_SUBVOLROOT=@" >> /etc/default/grub
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub 

# Install EFI bootloader
grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=void \
    --recheck

# Generate updated GRUB boot menu configuration file
grub-mkconfig -o /boot/grub/grub.cfg

exit
CHROOT_EOF

echo "=== Clean unmounting ==="
# Unmount virtual file systems in reverse order
umount /mnt/sys/firmware/efi/efivars 2>/dev/null || true
for dir in run sys proc dev; do
    umount "/mnt/$dir"
done

# Unmount core storage points
umount /mnt/boot/efi
umount /mnt/.snapshots
umount /mnt/home
umount /mnt

echo "=============================================================================="
echo "Success! Migration complete. You can now safely reboot your system."
echo "=============================================================================="
