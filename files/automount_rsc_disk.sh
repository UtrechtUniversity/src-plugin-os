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

do_mount()
{
    # Get info for this drive: $ID_FS_LABEL, $ID_FS_UUID, and $ID_FS_TYPE
    eval $(/sbin/blkid -o udev ${DEVICE})

    # Figure out a mount point to use
    LABEL=$(/opt/rsc-utilities/get_disk.sh $DEVBASE)
    if [[ -z "${LABEL}" ]]; then
        if [[ "${ID_FS_PARTLABEL}" ]]; then
             LABEL=${ID_FS_PARTLABEL}
        fi
    elif /bin/grep -q " /data/${LABEL} " /etc/mtab; then
        # Already in use, make a unique one
        LABEL+="-${DEVBASE}"
    fi
    MOUNT_POINT="/data/${LABEL}"

    echo "Mount point: ${MOUNT_POINT}"

    /bin/mkdir -p ${MOUNT_POINT}

    # Global mount options
    OPTS="rw,relatime"
    partition_uuid=$(blkid -s UUID -o value "$DEVICE")

    if grep -qF "$partition_uuid" /etc/fstab; then
        # Does nothing if there's an fstab entry for the device. user has to manually mount the device.
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Entry $data_directory already exists in /etc/fstab"
        exit 0
    else
        /bin/mount -o ${OPTS} ${DEVICE} ${MOUNT_POINT}
        if [ $? -eq 0 ]; then
            echo "UUID=$partition_uuid $MOUNT_POINT xfs defaults,nofail 0 0" >> /etc/fstab
            echo "Mounted ${DEVICE} at ${MOUNT_POINT}"
        else
            echo "Mounting ${DEVICE} at ${MOUNT_POINT} failed"
        fi
    fi

}

do_unmount()
{
    if [[ -z ${MOUNT_POINT} ]]; then
        echo "Warning: ${DEVICE} is not mounted"
    else
        /bin/umount -l ${DEVICE}
        ESCAPED_MOUNT_POINT=$(echo "$MOUNT_POINT" | sed 's/\//\\\//g')
        sed -i "/$ESCAPED_MOUNT_POINT/d" /etc/fstab
        echo "Unmounted ${DEVICE}"
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
        usage
        ;;
esac
