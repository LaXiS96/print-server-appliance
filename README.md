# Print Server Appliance

A set of scripts to prepare a disk image suitable for flashing to a Dell Wyse 3040, for it to act as a networked print server (using CUPS) to a USB-connected printer.

`build.sh` creates an EFI-bootable disk image of a minimal Debian system with the necessary packages installed.  
The root filesystem is mounted read-only for reliability, with an overlay for write persistence and logs in RAM.  
The output image is ran through `bmaptool` (a better `dd` that understands sparse files) and compressed with Gzip.  
If the persistent partition fails `fsck`, it is formatted and the system should still boot, though without any configuration.  
The persistent partition can also be formatted on request by adding `reset` to the kernel cmdline (in GRUB).  

`makeusb.sh` installs TinyCoreLinux to a block device (ie. USB drive), to be used for booting on the target system and flashing the disk image to the internal eMMC.  
The `bmap-rs` utility is built: requires [Rust](https://rustup.rs/) to build.

Tested on Fedora 43, requires packages `git gdisk python-bmaptools`.

1. Build the image with `./build.sh` (do not `sudo`)
2. Prepare the USB drive with `./makeusb.sh <device>` (do not `sudo`)
    - previously built `out.img` and `out.img.bmap` are copied to the USB's `/data` directory
3. Boot from the USB drive on the final system
4. Flash the image to internal storage:
    ```sh
    /mnt/sda2/bin/bmap-rs copy /mnt/sda2/data/out.img.gz /dev/mmcblk0
    # or
    zcat /mnt/sda2/data/out.img.gz | dd of=/dev/mmcblk0 bs=1M status=progress
    ```
5. Reboot and enjoy!

## CUPS
CUPS is configured via its web admin interface on `http://&lt;IP&gt;:631/` with a valid user and password (`root` usually).

Add your printer via `Administration` > `Find New Printers` and make sure to enable the `Share This Printer` option. Devices on your network (eg. Android phones) will automatically find the printer.

## Wi-Fi
Wi-Fi support is included in the image; the adapter can be inspected with `iw` and the connection can be configured via `/etc/network/interfaces` and `/etc/wpa_supplicant/wpa_supplicant.conf`.

If your adapter requires firmware, you must install its firmware package (eg. `firmware-mediatek` for MT7601U adapters). Look in the logs (ie. `journalctl`) for clues about missing firmware.

## Headless access
OpenSSH server is installed but defaults to not allowing root login with password. Either change the root password and ensure `PermitRootLogin yes` in `/etc/ssh/sshd_config`, or add your SSH key.

## TODO

- lower grub timeout?
- system seems still too bloated... what can we remove?
- [ ] fix gpt end-of-disk table after flashing
- [ ] move CUPS configuration to an additional partition (ro or rw?) so that formatting the persistent partition does not lose that too
- [ ] f2fs instead of ext4 for writable filesystem?
- [ ] autoexpand persistent partition on first boot?
- [ ] bmap-rs does not support lz4, though gzip --fast may be good enough
