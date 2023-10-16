#!/bin/bash
exec &>> /var/log/disk_mounting.log

partition=/dev/$1
data_directory=/data/$2

# Check if the device is already mounted
if mountpoint -q "$data_directory"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - A device is already mounted at $data_directory"
    exit 1
fi

if [ ! -d "$data_directory" ]; then
    #mkdir -p "$data_directory"
    mkdir -m 000 -p "$data_directory"
    #Turning off all bits in the mode is a simple indicator that nobody should be allowed to do anything in this directory until a 
    #new file system is mounted here. It's a message that this directory has been created as a mount point.
    #It is not required for #functionality, but sometimes avoids the mistakes of creating files when the desired volume is not mounted
fi

if grep -qF "$data_directory" /etc/fstab; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Entry $data_directory already exists in /etc/fstab"
else
    if [ -n "$partition" ] && [ -n "$data_directory" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Mounting $partition on $data_directory"
        /usr/bin/systemd-mount --fsck=no --no-block -G "$partition" "$data_directory" >> /var/log/disk_mounting.log 2>&1

            # Check if the mount operation was successful
            if [ $? -eq 0 ]; then
                # Add an entry to /etc/fstab using the partition's UUID
                partition_uuid=$(blkid -s UUID -o value "$partition")
                
                if [ -n "$partition_uuid" ]; then
                    # to enable growfs, add x-systemd.growfs to fstab line and do not create a partition on the disk during formatting.
                    echo "UUID=$partition_uuid $data_directory xfs defaults,x-systemd.device-timeout=9s,x-systemd.mount 0 0" >> /etc/fstab
                    #echo "UUID=$partition_uuid $data_directory xfs defaults,noauto,x-systemd.device-timeout=9s,x-systemd.automount 0 0" >> /etc/fstab
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - Mounting complete for directory: $data_directory"
                    chmod 777 $data_directory
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Failed to retrieve partition UUID."
                fi
            else
                systemctl start $data_directory
                if [ $? -eq 0 ]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Mounting failed for partition: $partition"
                fi
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Both partition and data_directory must be provided and non-empty."
    fi
fi
