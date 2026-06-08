sudo mount -o subvol=/ /dev/nvme0n1p3 /mnt

sudo btrfs subvolume snapshot /mnt /mnt/@
sudo btrfs subvolume create /mnt/@home
sudo btrfs subvolume create /mnt/.snapshots

sudo cp -a /mnt/home/. /mnt/@home/

cd /mnt
sudo rm -rf bin boot dev etc home lib lib64 media mnt opt proc root sbin srv sys tmp usr var

cd ~
sudo umount /mnt



sudo mount -o subvol=@,noatime,compress=zstd:1,ssd /dev/nvme0n1p3 /mnt

sudo mkdir -p /mnt/home /mnt/.snapshots /mnt/boot/efi

sudo mount -o subvol=@home,noatime,compress=zstd:1,ssd /dev/nvme0n1p3 /mnt/home
sudo mount /dev/nvme0n1p1 /mnt/boot/efi

