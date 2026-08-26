#!/bin/sh

if [ -w "$LXC_ROOTFS_PATH" ]; then
    rm -f "$LXC_ROOTFS_PATH/sbin/adbd"

    sed -i "/mount_all /d" "$LXC_ROOTFS_PATH"/init.*.rc
    sed -i "/swapon_all /d" "$LXC_ROOTFS_PATH"/init.*.rc
    sed -i "/on nonencrypted/d" "$LXC_ROOTFS_PATH/init.rc"

    run-parts /var/lib/lxc/android/pre-start.d || true
fi

mkdir -p /dev/__properties__ /dev/socket
