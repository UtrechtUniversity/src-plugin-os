#!/bin/bash

# Ensure that the script is called with the correct number of arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 directory_name device_path"
    exit 1
fi

# Extract arguments
directory_name="$1"
device_path="$2"
partition="$2"1

# Directory path under /data
data_directory="/data/$directory_name"

# Create the directory if it doesn't exist
if [ ! -d "$data_directory" ]; then
    mkdir -p "$data_directory"
fi

# Check if the device is already mounted
if mountpoint -q "$data_directory"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - A device is already mounted at $data_directory"
    exit 1
fi

# Check if the entry is already present in /etc/fstab using UUID
if grep -qF "$data_directory" /etc/fstab; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Entry already exists in /etc/fstab"
else
    # Check if the device has a partition table using sfdisk
    if sfdisk -d "$device_path" >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Disk $device_path has partitions"
    else
        if [ -n "$(blkid -o value -s TYPE "$device_path")" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Existing filesystem found on $device_path"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Disk $device_path is raw and safe to format"
            # Format the disk with xfs
            sgdisk -o $device_path
            echo "$(date '+%Y-%m-%d %H:%M:%S') - made gpt label for $device_path"

            sgdisk --new 1::0 $device_path
            echo "$(date '+%Y-%m-%d %H:%M:%S') - partition "$device_path"1 created"

            mkfs.xfs "$device_path"1
            echo "$(date '+%Y-%m-%d %H:%M:%S') - ${device_path}1 formatted as XFS"

            xfs_admin -L "$directory_name" "$device_path"1
            echo "$(date '+%Y-%m-%d %H:%M:%S') - XFS label added"
            
            sleep 2;
            partprobe "$device_path"
        fi
    fi
    
    # Check if the mount operation was successful
    if [ -n "$partition" ] && [ -n "$data_directory" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Mounting $partition on $data_directory"
        #mount "$partition" "$data_directory"
        /usr/bin/systemd-mount -G "$partition" "$data_directory"
        
        # Check if the mount operation was successful
        if [ $? -eq 0 ]; then
            # Add an entry to /etc/fstab using the partition's UUID
            partition_uuid=$(blkid -s UUID -o value "$partition")
            
            if [ -n "$partition_uuid" ]; then
                echo "UUID=$partition_uuid $data_directory xfs defaults 0 0" >> /etc/fstab
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Mounting complete for directory: $data_directory"
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Failed to retrieve partition UUID."
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Mounting failed for partition: $partition"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Both partition and data_directory must be provided and non-empty."
    fi

fi
