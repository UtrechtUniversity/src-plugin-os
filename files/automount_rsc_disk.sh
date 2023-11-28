#!/bin/bash

# This script is called from rsc-mount-disk systemd unit file to mount or unmount an rsc disk.

usage()
{
    echo "Usage: $0 device_name (e.g. vdb1)"
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
fi

DEVBASE=$1
DEVICE="/dev/${DEVBASE}"

# See if this drive is already mounted, and if so where
MOUNT_POINT=$(/bin/mount | /bin/grep -w ${DEVICE} | /usr/bin/awk '{ print $3 }')
echo "Device is mounted at $MOUNT_POINT"

do_mount()
{
    # Get info for this drive: $ID_FS_LABEL, $ID_FS_UUID, and $ID_FS_TYPE
    eval $(/sbin/blkid -o udev ${DEVICE})

    # Figure out a mount point to use
    MAX_RETRIES=3
    RETRY_COUNT=0

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        LABEL=$(/opt/rsc-utilities/get_disk.sh $DEVBASE)

        if [ -n "$LABEL" ]; then
            # The result is not empty, break out of the loop
            break
        else
            # Increment the retry count and wait before trying again
            RETRY_COUNT=$((RETRY_COUNT + 1))
            sleep 1  # Adjust the sleep duration as needed
        fi
    done

    if [[ -z "${LABEL}" ]]; then
        if [[ "${ID_FS_PARTLABEL}" ]]; then
             LABEL=${ID_FS_PARTLABEL}
        fi
    elif /bin/grep -q " /data/${LABEL} " /etc/mtab; then
        # Already in use, make a unique one
        LABEL+="-${DEVBASE}"
    fi
    
    MOUNT_POINT="/data/${LABEL}"
    
    # Check if MOUNT_POINT is "/data/"
    if [ "$MOUNT_POINT" = "/data/" ]; then
        echo "Mount point is /data/. Exiting the script."
        exit 1
    fi

    echo "Mount point: ${MOUNT_POINT}"
    
    MAX_RETRIES=5
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # Check if the device is ready
        # xfs_info $DEVICE could also be used for the check
        if [ -n "$(blkid -s UUID -o value "$DEVICE")" ]; then
            echo "Device $DEVICE is ready."
            break
        else
            echo "Device $DEVICE not ready. Retrying in 2 seconds..."
            RETRY_COUNT=$((RETRY_COUNT + 1))
            sleep 2
        fi
    done

    # Mount the partition if it's ready
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo "Failed to detect $DEVICE after $MAX_RETRIES retries. Exiting."
        exit 1
    fi

    /bin/mkdir -p ${MOUNT_POINT}

    # Global mount options
    OPTS="rw,relatime"
    partition_uuid=$(blkid -s UUID -o value "$DEVICE")

    /bin/mount -o ${OPTS} ${DEVICE} ${MOUNT_POINT}
    if [ $? -eq 0 ]; then
        if grep -qF "$partition_uuid" /etc/fstab; then
            # Does not add to fstab if there's an fstab entry for the device.
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Entry $data_directory already exists in /etc/fstab"
        else
            echo "UUID=$partition_uuid $MOUNT_POINT xfs defaults,nofail 0 0" >> /etc/fstab
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
