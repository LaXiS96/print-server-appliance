#!/bin/bash

qemu-system-x86_64 \
    -accel kvm \
    -smp 4 \
    -m 2G \
    -drive file=out/out.img,format=raw \
    -bios /usr/share/edk2/ovmf/OVMF_CODE.fd #\
    # -serial mon:stdio \
