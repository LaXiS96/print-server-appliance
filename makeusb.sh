#!/bin/bash
set -Eeu -o pipefail

# Prepares an USB drive with a TinyCoreLinux bootable image
# TODO cache tczs in stage like build.sh?

: "${TINYCORE_BASE_URL:="http://tinycorelinux.net/17.x/x86_64"}"
: "${LINUX_URL:="$TINYCORE_BASE_URL/release/distribution_files/vmlinuz64"}"
: "${INITRD_URL:="$TINYCORE_BASE_URL/release/distribution_files/corepure64.gz"}"
: "${TCZ_URL:="$TINYCORE_BASE_URL/tcz"}"
: "${TCZS:="bzip2 coreutils efibootmgr file gzip lz4 openssl xz"}"
: "${BMAP_RS_GIT:="https://github.com/collabora/bmap-rs.git"}"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <device>" >&2
    exit 1
fi

dev=$(readlink -f "$1")
if [[ ! -b $dev ]]; then
    echo "Error: $dev is not a block device" >&2
    exit 1
fi

read -p "Device: $dev ($(lsblk -dno SIZE "$dev")) [y/N] " -n 1 -r; echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting" >&2
    exit 1
fi

mnt=$(mktemp --directory)
mnt_boot=$mnt/boot
mnt_data=$mnt/data

unmount() {
    sudo umount --quiet "$mnt_boot"
    sudo umount --quiet "$mnt_data"
}

onerror() {
    local exit=$?
    set +e
    unmount
    echo "Failed with exit code: $exit"
    exit $exit
}
trap onerror ERR

if [[ ! -d bmap-rs/.git ]]; then
    git clone -o bmap-rs "$BMAP_RS_GIT"
fi

if [[ ! -f bmap-rs/target/release/bmap-rs ]]; then
    ( cd bmap-rs && cargo build --release )
fi

sudo sgdisk \
    --clear \
    --new=1:0:550M --typecode=1:ef00 \
    --new=2:0:0    --typecode=2:0700 \
    "$dev"
sudo mkfs.vfat -F32 "${dev}1"
sudo mkfs.ext4 -F "${dev}2"

mkdir -p "$mnt_boot"
mkdir -p "$mnt_data"
sudo mount "${dev}1" "$mnt_boot"
sudo mount "${dev}2" "$mnt_data"

# On Fedora 43:
sudo grub2-install \
    --target=x86_64-efi \
    --efi-directory="$mnt_boot" \
    --boot-directory="$mnt_boot/boot/" \
    --removable --force

echo "Retrieving kernel and initrd"
sudo curl --progress-bar -o "$mnt_boot/boot/linux" "$LINUX_URL"
sudo curl --progress-bar -o "$mnt_boot/boot/initrd" "$INITRD_URL"

data_part="UUID=\"$(sudo blkid --match-tag UUID --output value "${dev}2")\""
sudo tee "$mnt_boot/boot/grub2/grub.cfg" >/dev/null <<EOF
set timeout=5
set default=0
menuentry "Tiny Core Linux" {
    linux /boot/linux norestore waitusb=5 tce="$data_part" opt="$data_part"
    initrd /boot/initrd
}
EOF

sudo mkdir -p "$mnt_data/data"
sudo chmod 777 "$mnt_data/data"
if [[ -f out/out.img.gz ]]; then
    echo "Copying out.img"
    cp --verbose out/out.img.gz out/out.img.bmap "$mnt_data/data/"
    sync "$mnt_data/data/out.img.gz"
fi

sudo mkdir -p "$mnt_data/opt"
sudo tee "$mnt_data/opt/bootlocal.sh" >/dev/null <<EOF
#!/bin/sh
# Fix dynamically linked binaries referencing /lib64
ln -s /lib /lib64
EOF
sudo chmod a+x "$mnt_data/opt/bootlocal.sh"

# Find and deduplicate TCZs' dependencies
tcz_deps=""
for tcz in $TCZS; do
    tcz_deps+="$tcz.tcz"$'\n'
    # The "/<name>.tcz.dep" request returns a list of dependencies or 404 if
    # there are none
    tcz_deps+="$(curl --silent --fail "$TCZ_URL/$tcz.tcz.dep" || true)"$'\n'
done
tcz_deps="$(grep -v '^$' <<<"$tcz_deps" | sort -u)"

# Download TCZs
sudo mkdir -p "$mnt_data/tce/optional"
while IFS= read -r dep; do
    echo "Retrieving $dep"
    sudo curl --progress-bar -o "$mnt_data/tce/optional/$dep" "$TCZ_URL/$dep"
    sudo tee -a "$mnt_data/tce/onboot.lst" >/dev/null <<<"$dep"
done <<<"$tcz_deps"

sudo mkdir -p "$mnt_data/bin"
sudo cp bmap-rs/target/release/bmap-rs "$mnt_data/bin/"

echo "Finishing up"
unmount
