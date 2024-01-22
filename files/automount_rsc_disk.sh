#!/bin/bash

# This script is called from rsc-mount-disk systemd unit file to mount or unmount an rsc disk.

usage()
{
    echo "Usage: $0 device_name (e.g. vdb1)"
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

storage_config="/etc/rsc/storage.json"
workspace_data=$(cat "$storage_config")
volume_mount_no_name=$(echo "$workspace_data" | jq -r '.volume_mount_no_name')
DEVBASE=$1
DEVICE="${DEVBASE}1"
DISK_NAME=$2
FILESYSTEM="xfs"
partition_uuid=$(blkid -s UUID -o value "$DEVICE")

get_partition_info()
{
    part_info=$(/bin/lsblk -lp -o NAME,FSTYPE,TYPE,UUID -n $DEVBASE | awk '($2!=""  && (($3=="disk" && ($2!="vfat" && $2!="swap")) || ($3=="part" && $2!="swap"))) { print "{\"file_system\":\""$2"\",\"name\":\""$1"\",\"uuid\":\""$4"\"}" }')
    DEVICE=$(echo "$part_info" | jq -r '.name')
    FILESYSTEM=$(echo "$part_info" | jq -r '.file_system')
    partition_uuid=$(echo "$part_info" | jq -r '.uuid')
}

get_partition_info

mkdir -p /data/
chmod 777 /data/

if /bin/mount | /bin/grep -w ${DEVICE}; then
    MOUNTED_AT=$(/bin/mount | /bin/grep -w ${DEVICE} | /usr/bin/awk '{ print $3 }')
    echo "Device is already mounted at $MOUNTED_AT"
    exit 0;
fi

do_mount()
{
    # Get info for this drive: $ID_FS_LABEL, $ID_FS_UUID, and $ID_FS_TYPE
    eval $(/sbin/blkid -o udev ${DEVICE})

    if [ "$volume_mount_no_name" = true ]; then
        LABEL=$(get_disk_number)
    else
        LABEL=$DISK_NAME
    fi

    if [[ -z "${LABEL}" ]]; then
        if [[ "${ID_FS_PARTLABEL}" ]]; then
             LABEL=${ID_FS_PARTLABEL}
        fi
    elif /bin/grep -q " /data/${LABEL} " /etc/mtab; then
        # Already in use
        echo "Already mounted at /data/${LABEL}"
        exit 0
        #LABEL+="-${DEVBASE}"
    fi
    
    MOUNT_POINT="/data/${LABEL}"
    
    # Check if MOUNT_POINT is "/data/"
    if [ "$MOUNT_POINT" = "/data/" ]; then
        echo "Mount point is /data/. Exiting the script."
        exit 1
    fi

    echo "Mount point: ${MOUNT_POINT}"
    
    wait_for_device

    /bin/mkdir -p ${MOUNT_POINT}

    # Global mount options
    OPTS="x-mount.mkdir"

    /bin/mount -o ${OPTS} ${DEVICE} ${MOUNT_POINT}
    if [ $? -eq 0 ]; then
        if [ "$volume_mount_no_name" != true ]; then
            if grep -qF "UUID=$partition_uuid $MOUNT_POINT" /etc/fstab; then
                # Does not add to fstab if there's an fstab entry for the device.
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Entry $MOUNT_POINT already exists in /etc/fstab"
            else
                #check if mountpoint exist in fstab, if so, remove it.
                if grep -qwF "$MOUNT_POINT" /etc/fstab; then
                    ESCAPED_MOUNT_POINT=$(echo "$MOUNT_POINT" | sed 's/\//\\\//g')
                    echo "Escaped mount point: $ESCAPED_MOUNT_POINT"
                    sed -i "/$ESCAPED_MOUNT_POINT/d" /etc/fstab
                fi
                echo "UUID=$partition_uuid $MOUNT_POINT $FILESYSTEM defaults,nofail,x-mount.mkdir 0 0" >> /etc/fstab
            fi
        else
            if grep -qF "UUID=$partition_uuid" /etc/fstab; then
                # Does not add to fstab if there's an fstab entry for the device.
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Entry UUID=$partition_uuid already exists in /etc/fstab"
            else
                echo "UUID=$partition_uuid $MOUNT_POINT $FILESYSTEM defaults,nofail,x-mount.mkdir 0 0" >> /etc/fstab
            fi
        fi
        echo "Mounted ${DEVICE} at ${MOUNT_POINT}"
    else
        echo "Mounting ${DEVICE} at ${MOUNT_POINT} failed"
    fi
}

do_unmount()
{
    if [[ -z ${MOUNT_POINT} ]]; then
        echo "Warning: ${DEVICE} is not mounted"
    else
        ESCAPED_MOUNT_POINT=$(echo "$MOUNT_POINT" | sed 's/\//\\\//g')
        echo "Escaped mount point: $ESCAPED_MOUNT_POINT"
        sed -i "/$ESCAPED_MOUNT_POINT/d" /etc/fstab
        /bin/umount -l ${DEVICE}
        echo "Unmounted device ${DEVICE}"
    fi
}

get_disk_number()
{
    max_attempts=100

    next_number=1
    while ((next_number <= max_attempts)); do
        if ! grep -qw "/data/volume_${next_number}" /etc/fstab; then
            echo "volume_${next_number}"
            return
        fi
        ((next_number++))
    done

    echo "Error: Unable to find an available volume number after $max_attempts attempts." >&2
    exit 1
}

wait_for_device() 
{
    local MAX_RETRIES=5
    local RETRY_COUNT=0

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # Check if the device is ready
        # xfs_info $DEVICE could also be used for the check
        if [ -n "$(blkid -s UUID -o value "$DEVICE")" ]; then
            echo "Device $DEVICE is ready."
            return 0  # Success
        else
            echo "Device $DEVICE not ready. Retrying in 2 seconds..."
            RETRY_COUNT=$((RETRY_COUNT + 1))
            sleep 2
        fi
    done

    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo "Failed to detect $DEVICE after $MAX_RETRIES retries. Exiting."
        exit 1
    fi
}

if ! [ -b $DEVICE ]
then
    if grep /etc/mtab -wqe "^$DEVICE"
    then
        echo "$DEVICE device removed, umounting..."
        ACTION="remove"
    fi
else
        ACTION="add"
fi

case "${ACTION}" in
    add)
        do_mount
        ;;
    remove)
        do_unmount
        ;;
    *)
        echo "Action is not valid"
        ;;
esac

