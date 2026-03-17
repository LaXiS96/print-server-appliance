#!/bin/bash
set -Eeu -o pipefail

STAGE_DIR=stage
OUT_DIR=out
DEBS_DIR="$STAGE_DIR/debootstrap"
DEBS_GIT=https://salsa.debian.org/installer-team/debootstrap.git
DEBS_VER=1.0.142
DEBS_BIN="$DEBS_DIR/debootstrap"
DEBS_CACHE="$STAGE_DIR/debcache"
DEBIAN_SUITE=stable
IMAGE=out.img
IMAGE_SIZE=4G
HOSTNAME=printserver

mnt=$(mktemp --directory)
loop=""

enter() {
    echo ">>> chroot: $*"
    sudo chroot "$mnt" env -i \
        TERM="$TERM" \
        PATH=/sbin:/bin:/usr/sbin:/usr/bin \
        "$@"
}

cleanup() {
    sudo umount --recursive --quiet "$mnt" || true
    [[ $loop ]] && sudo losetup --detach "$loop" || true
    rmdir "$mnt" || true
}

onerror() {
    local exit=$?
    echo "!!! Failed with exit code: $exit, command: $BASH_COMMAND" >&2
    cleanup
    exit $exit
}
trap onerror ERR

if [[ ! -d $DEBS_DIR ]]; then
    git clone --branch "$DEBS_VER" -- "$DEBS_GIT" "$DEBS_DIR"
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

if [[ ! -f "$STAGE_DIR/$IMAGE" ]]; then
    echo ">>> Creating $STAGE_DIR/$IMAGE ($IMAGE_SIZE)"
    truncate --size="$IMAGE_SIZE" "$OUT_DIR/$IMAGE"
    base_install=true
else
    echo ">>> Using $STAGE_DIR/$IMAGE"
    cp "$STAGE_DIR/$IMAGE" "$OUT_DIR/$IMAGE"
    base_install=false
fi

loop=$(sudo losetup --find "$OUT_DIR/$IMAGE" --partscan --show)
echo ">>> Loop device: $loop"

if $base_install; then
    echo ">>> Partitioning"
    sudo sgdisk --clear \
        --new=1:1M:+550M --typecode=1:ef00 \
        --new=2:0:+2G    --typecode=2:8300 \
        --new=3:0:0      --typecode=3:8300 \
        "$loop"

    echo ">>> Formatting"
    sudo mkfs.vfat -F32 "${loop}p1"
    sudo mkfs.ext4 -L root "${loop}p2"
    sudo mkfs.ext4 -L persist "${loop}p3"
fi

mkdir -p "$mnt"
sudo mount "${loop}p2" "$mnt"

if $base_install; then
    echo ">>> Installing base system"
    mkdir -p "$DEBS_CACHE"
    sudo DEBOOTSTRAP_DIR="$DEBS_DIR" $DEBS_BIN \
        --arch=amd64 \
        --cache-dir="$(realpath "$DEBS_CACHE")" \
        "$DEBIAN_SUITE" "$mnt"
fi

sudo mount --bind /dev "$mnt/dev"
sudo mount --bind /proc "$mnt/proc"
sudo mount --bind /sys "$mnt/sys"

sudo mkdir -p "$mnt/boot/efi"
sudo mount "${loop}p1" "$mnt/boot/efi"

if $base_install; then
    enter apt update
    # https://wiki.archlinux.org/title/Systemd-nspawn#Create_a_Debian_or_Ubuntu_environment
    enter apt install -y \
        linux-image-amd64 \
        grub-efi-amd64-signed \
        dbus \
        libpam-systemd \
        systemd-timesyncd \
        openssh-server

    cp "$OUT_DIR/$IMAGE" "$STAGE_DIR/$IMAGE"
fi

echo ">>> Installing GRUB"
# https://blog.roberthallam.org/2020/05/psa-dell-wyse-3040-uses-fallback-efi-location/
# https://www.rodsbooks.com/efi-bootloaders/fallback.html
# Install GRUB to /EFI/debian
enter grub-install \
    --target=x86_64-efi \
    --uefi-secure-boot \
    --bootloader-id=debian \
    --no-nvram
# Set up EFI fallback /EFI/BOOT
# shimx64 (BOOTX64.EFI) hands off to fbx64 which creates boot entries in NVRAM
# based on the BOOTX64.CSV file it finds in /EFI/debian
sudo mkdir -p "$mnt/boot/efi/EFI/BOOT"
sudo cp "$mnt/boot/efi/EFI/debian/shimx64.efi" "$mnt/boot/efi/EFI/BOOT/BOOTX64.EFI"
sudo cp "$mnt/boot/efi/EFI/debian/fbx64.efi" "$mnt/boot/efi/EFI/BOOT/fbx64.efi"
sudo cp "$mnt/boot/efi/EFI/debian/mmx64.efi" "$mnt/boot/efi/EFI/BOOT/mmx64.efi"
sudo cp "$mnt/boot/efi/EFI/debian/grubx64.efi" "$mnt/boot/efi/EFI/BOOT/grubx64.efi"
enter update-grub

sudo tee "$mnt/etc/hostname" <<<"$HOSTNAME" >/dev/null
echo "root:changeme" | enter chpasswd
sudo install --mode=0644 files/interfaces "$mnt/etc/network/interfaces"
sudo install --mode=0644 files/fstab "$mnt/etc/fstab"
sudo install --mode=0755 files/overlay "$mnt/etc/initramfs-tools/scripts/init-bottom/overlay"
sudo install --mode=0755 files/overlayhook "$mnt/etc/initramfs-tools/hooks/overlay"
sudo tee -a "$mnt/etc/initramfs-tools/modules" <<<"overlay" >/dev/null
enter update-initramfs -u -k all

# https://wiki.debian.org/SystemPrinting
# https://packages.debian.org/stable/printer-driver-all
# https://wiki.debian.org/CUPSPrintQueues#nonfree
# https://wiki.debian.org/Avahi
enter apt install -y \
    cups \
    printer-driver-all \
    avahi-daemon
# TODO cupsd.conf

echo ">>> Finalizing image"
enter apt clean
sudo rm -rf "$mnt/var/lib/apt/lists/*" "$mnt/var/cache/*" "$mnt/var/log/*"

sudo umount --recursive --quiet "$mnt"
sudo fsck.fat -a "${loop}p1" || true
sudo e2fsck -fp "${loop}p2" || true
sudo losetup --detach "$loop"
loop=""

python -m bmaptool create -o "$OUT_DIR/$IMAGE.bmap" "$OUT_DIR/$IMAGE"
gzip --fast --stdout --force --verbose "$OUT_DIR/$IMAGE" >"$OUT_DIR/$IMAGE.gz"

echo ">>> Done!"
cleanup
