# shellcheck shell=sh

# Copyright (C) 2021-2022 UBports Foundation.
# SPDX-License-Identifier: GPL-3.0-or-later

# Cache for partition name to device mapping from sysfs
partname_cache=""
partname_cache_built=""

# Build partition name cache from /sys/class/block/*/uevent
# This is used as a fallback when /dev/disk/by-* is not yet available (before udev coldboot)
build_partname_cache() {
    if [ -n "$partname_cache_built" ]; then
        return
    fi

    partname_cache=""
    for uevent in /sys/class/block/*/uevent; do
        [ -e "$uevent" ] || continue

        devname=""
        partname=""

        while IFS='=' read -r key value; do
            case "$key" in
                DEVNAME)
                    devname="$value"
                    ;;
                PARTNAME)
                    partname="$value"
                    ;;
            esac
        done < "$uevent"

        if [ -n "$devname" ] && [ -n "$partname" ]; then
            # Store as "partname:devname" pairs, newline separated
            if [ -z "$partname_cache" ]; then
                partname_cache="${partname}:${devname}"
            else
                partname_cache="${partname_cache}
${partname}:${devname}"
            fi
        fi
    done

    partname_cache_built=1
}

# Lookup partition by name in the cache
# $1=partition name
# Returns device path if found
lookup_partname_cache() {
    search_name="$1"

    build_partname_cache

    echo "$partname_cache" | while IFS=: read -r partname devname; do
        if [ "$partname" = "$search_name" ]; then
            echo "/dev/${devname}"
            return 0
        fi
    done
}

# Grabbed and modified from Debian's initramfs-tools (GPL-2.0-or-later).
# Resolve device node from a name
# Supports PARTLABEL= lookups without requiring blkid
# $1=name
# Resolved name is echoed.
resolve_device() {
    DEV="$1"

    case "$DEV" in
    PARTLABEL=*)
        partlabel="${DEV#PARTLABEL=}"
        DEV="$(lookup_partname_cache "$partlabel")" || return 1
        ;;
    esac
    [ -e "$DEV" ] && echo "$DEV"
}

ab_slot_detect_done=""
ab_slot_suffix=""

find_partition_path() {
    # Note that we run early before udev coldboot, so if we boot without initrd,
    # /dev/disk/by-* might not be available. We rely on PARTLABEL lookups that
    # fall back to cached /sys/class/block metadata.

    if [ -z "$ab_slot_detect_done" ]; then
        if [ -e /proc/bootconfig ]; then
            ab_slot_suffix=$(grep -o 'androidboot\.slot_suffix = ".."' /proc/bootconfig | cut -d '"' -f2)
        fi
        if [ -z "$ab_slot_suffix" ]; then
            ab_slot_suffix=$(grep -o 'androidboot\.slot_suffix=..' /proc/cmdline |  cut -d "=" -f2)
        fi
        if [ -n "$ab_slot_suffix" ]; then
            echo "Detected slot suffix $ab_slot_suffix" >&2
        fi
        ab_slot_detect_done=1
    fi

    for detection in \
            /dev/mapper/ \
            /dev/block/mapper/ \
            /dev/disk/by-partlabel/ \
            PARTLABEL= \
    ; do
        if resolve_device "${detection}${1}"; then
            break
        fi

        if [ -n "$ab_slot_suffix" ] && \
                resolve_device "${detection}${1}${ab_slot_suffix}"; then
            break
        fi
    done
}

