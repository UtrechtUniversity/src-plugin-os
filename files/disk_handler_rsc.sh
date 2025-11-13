#!/bin/bash

log_file="/var/log/disk_mounting.log"
storage_config="/etc/rsc/storage.json"

# Check if the storage configuration file exists
if [ ! -f "$storage_config" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Storage configuration file not found at $storage_config" 
    exit 1
fi

# Read storage data from JSON file
workspace_data=$(cat "$storage_config")

# Parse storage data to get required values
co_token=$(echo "$workspace_data" | jq -r '.co_token')
workspace_id=$(echo "$workspace_data" | jq -r '.workspace_id')
storage_api_endpoint=$(echo "$workspace_data" | jq -r '.storage_api_endpoint')

disk_serial_to_path()
{
    readlink -f $(ls /dev/disk/by-id/*$1* | grep -v part | head -1)
}

# Execute the curl request and retrieve storages data
retry_count=0
max_retries=10
retry_delay=5

while [ $retry_count -lt $max_retries ]; do
    curl_output=$(curl -s "$storage_api_endpoint/$workspace_id/" -H "authorization: $co_token" -H "content-type: application/json")

    # Check if the response contains volume_name and volume_id
    if [ -n "$curl_output" ]; then
        jq -c '.meta.storages | .[]' <<< "$curl_output" | while IFS= read -r storage; do
        
            volume_name=$(echo "$storage" | jq -r '.name' | tr ' ' '_')
            volume_id=$(echo "$storage" | jq -r '.volume_id' | cut -c 1-20)

            if [ "$volume_name" = "null" ] || [ "$volume_id" = "null" ] || [ "$volume_name" = "" ]; then
                echo "Key or volume_id is 'null'. Retrying..." >> "$log_file" 2>&1
                # fix retry 
                continue
            fi
            volume_path=$(disk_serial_to_path $volume_id)
            /opt/rsc-utilities/format_rsc_disk.sh $volume_path $volume_name #add error handling, should move to the next item if failed.
            sleep 5
            /opt/rsc-utilities/automount_rsc_disk.sh $volume_path $volume_name
            echo $(date) "Volume path: $volume_path ,Volume name: $volume_name ,Volume ID: $volume_id" >> "$log_file" 2>&1
        done
        break
    else
        echo "Retry $((retry_count + 1)): unable to reach the endpoint. Retrying in $retry_delay seconds..." >> "$log_file" 2>&1
        sleep $retry_delay
        retry_count=$((retry_count + 1))
    fi
done

if [ $retry_count -eq $max_retries ]; then
    echo "Maximum retries exceeded. Disk ID match not found."
    exit 1
fi

# Cleanup only RSC-managed empty directories with extra safety checks
find "/data" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    ! -name "datasets" \
    ! -name ".*" \
    -exec sh -c '
        for dir do
            if [ ! -f "$dir/.rsc_managed" ]; then
                continue  # Skip if not RSC managed
            fi

            if mountpoint -q "$dir"; then
                continue  # Skip if directory is a mountpoint
            fi

            # Check for any entries other than the marker (efficient, returns immediately if any)
            if [ -n "$(find "$dir" -mindepth 1 -maxdepth 1 ! -name ".rsc_managed" -print -quit 2>/dev/null)" ]; then
                continue  # Skip if directory has other files
            fi

            rm -f "$dir/.rsc_managed" && \
            rmdir "$dir" && \
            echo "$(date) - Successfully removed empty managed mountpoint $dir" >> '"$log_file"'
        done
    ' sh {} +
