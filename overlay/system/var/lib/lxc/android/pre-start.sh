#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Reusable Moto E 2020 (ginna) Ubuntu Touch / Android LXC boot diagnostic.
# It is intended for active port debugging. Each boot appends host and Android
# evidence to /userdata/gin-debug.log, while retaining a bounded recent history.
# Remove this overlay when the port no longer needs continuous diagnostics.

LOG=/userdata/gin-debug.log
MAX_BYTES=4194304
KEEP_BYTES=3145728

trim_log() {
    [ -e "$LOG" ] || return 0
    size=$(wc -c < "$LOG" 2>/dev/null || echo 0)
    [ "$size" -le "$MAX_BYTES" ] && return 0
    tail -c "$KEEP_BYTES" "$LOG" > "${LOG}.new" 2>/dev/null && \
        mv "${LOG}.new" "$LOG"
}

trim_log

{
    echo
    echo '============================================================'
    echo '=== ginna unified boot diagnostic: session start ==='
    date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true
    echo '--- host kernel command line ---'
    cat /proc/cmdline 2>&1 || true
    echo '--- host cgroup mounts ---'
    grep -E 'cgroup|cgroup2' /proc/mounts 2>&1 || true
    echo '--- host QSEECOM device ---'
    ls -l /dev/qseecom 2>&1 || true
    if [ -c /dev/qseecom ]; then
        echo 'host result: /dev/qseecom is a character device'
    else
        echo 'host result: /dev/qseecom is absent or not a character device'
    fi
    echo '--- host QSEECOM registration ---'
    grep -i qsee /proc/devices 2>&1 || true
    echo '--- active Android LXC QSEECOM mapping ---'
    grep -n '/dev/qseecom' /var/lib/lxc/android/config 2>&1 || true
    echo '--- host kernel log snapshot ---'
    dmesg 2>&1 | tail -n 350 || true
    echo '--- Android LXC probe scheduled ---'
    echo '=== host diagnostic complete ==='
} >> "$LOG" 2>&1

# Preserve upstream Android LXC pre-start behavior.
if [ -w "$LXC_ROOTFS_PATH" ]; then
    rm "$LXC_ROOTFS_PATH/sbin/adbd"

    sed -i "/mount_all /d" "$LXC_ROOTFS_PATH"/init.*.rc
    sed -i "/swapon_all /d" "$LXC_ROOTFS_PATH"/init.*.rc
    sed -i "/on nonencrypted/d" "$LXC_ROOTFS_PATH/init.rc"

    run-parts /var/lib/lxc/android/pre-start.d || true
fi

mkdir -p /dev/__properties__ /dev/socket

# The LXC container starts after this hook returns. Capture one container-side
# device probe and then up to three minutes of Android logcat in the background.
(
    attempt=0
    while [ "$attempt" -lt 60 ]; do
        attempt=$((attempt + 1))
        if lxc-attach -n android -- /system/bin/sh -c '
            echo "--- Android container diagnostic ---"
            echo "container identity: $(id 2>&1)"
            echo "container /dev/qseecom:"
            ls -l /dev/qseecom 2>&1 || true
            if [ -c /dev/qseecom ]; then
                echo "container result: /dev/qseecom is a character device"
            else
                echo "container result: /dev/qseecom is absent or not a character device"
            fi
            echo "container QSEE mount references:"
            mount 2>&1 | grep -i qsee || true
            echo "--- end Android container diagnostic ---"
        ' >> "$LOG" 2>&1; then
            echo '--- Android logcat capture begins (maximum 180 seconds) ---' >> "$LOG"
            timeout 180 lxc-attach -n android -- /system/bin/logcat -b all -v threadtime \
                >> "$LOG" 2>&1 || true
            echo '--- Android logcat capture ended ---' >> "$LOG"
            trim_log
            exit 0
        fi
        sleep 1
    done
    echo 'ERROR: Android LXC never became attachable for diagnostic capture' >> "$LOG"
    trim_log
) &

exit 0
