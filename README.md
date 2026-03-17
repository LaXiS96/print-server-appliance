# Print Server Appliance

A set of scripts to prepare a disk image suitable for flashing to a Dell Wyse 3040, for it to act as a networked print server (using CUPS) to a USB-connected printer.

`build.sh` creates an EFI-bootable disk image of a minimal Debian system with the necessary packages installed.  
The root filesystem is mounted read-only for reliability, with an overlay for write persistence and logs in RAM.  
The output image is ran through `bmaptool` (a better `dd` that understands sparse files) and compressed with Gzip.  
If the persistent partition fails `fsck`, it is formatted and the system should still boot, though with no configuration.  
The persistent partition can also be formatted on request by adding `reset` to the kernel cmdline (in GRUB).  

`makeusb.sh` installs TinyCoreLinux to a block device (ie. USB drive), to be used for booting on the target system and flashing the disk image to the internal eMMC.  
The native `bmap-rs` utility is built: requires [Rust](https://rustup.rs/) to build.

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

## TODO

- [ ] move CUPS configuration to an additional partition (ro or rw?) so that formatting the persistent partition does not lose that too
- [ ] f2fs instead of ext4 for writable filesystem?
- [ ] autoexpand persistent partition on first boot?
- [ ] bmap-rs does not support lz4, though gzip --fast may be good enough
