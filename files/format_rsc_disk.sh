#!/bin/bash

# Ensure that the script is called with the correct number of arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 device_path"
    exit 1
fi

# Extract arguments
device_path=$1
directory_name=$2
if [[ $device_path == *nvme* ]]; then
    partition="${device_path}p1"
else
    partition="${device_path}1"
fi

# Check if the device has a partition table using sfdisk
if parted -s "$device_path" print | grep -q "Partition Table: \(gpt\|msdos\)"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Existing filesystem found on $device_path"
else
    if  blkid -o value -s TYPE "$device_path" &> /dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Existing filesystem found on $device_path"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Disk $device_path is raw and safe to format"
        # Format the disk with xfs
        sgdisk -o $device_path
        echo "$(date '+%Y-%m-%d %H:%M:%S') - made gpt label for $device_path"
        
        sgdisk --new 1::0 $device_path
        echo "$(date '+%Y-%m-%d %H:%M:%S') - partition "$partition" created"
        #Setting GPT PARTLABEL
        sgdisk -c 1:"$directory_name" "$device_path"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - GPT Partition lable $directory_name created for device $device_path"

        mkfs.xfs $partition
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ${partition} formatted as XFS"

        xfs_admin -L "$directory_name" "$partition"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - XFS label added for device $partition"
    fi
fi

sleep 1

