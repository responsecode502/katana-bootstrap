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

sudo xbps-install -u xbps
sudo xbps-install -Sy nano

'''
UUID=4d4d1973-02bf-4220-83d4-f7c570937b79    /    btrfs rw,noatime,compress=zstd:1,ssd,subvol=@ 0 0
UUID=4d4d1973-02bf-4220-83d4-f7c570937b79    /home    btrfs rw,noatime,compress=zstd:1,ssd,subvol=@home 0 0
UUID=4A64-8B5A    /boot/efi    vfat rw,noatime,fmask=0077,dmask=0077 0 2
'''

sudo mount -a

grub-install /dev/nvme0n1
update-grub