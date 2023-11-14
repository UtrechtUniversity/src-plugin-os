#!/bin/bash

device=$1
device_path=/dev/$1
log_file="/var/log/disk_mounting.log"
storage_config="/etc/rsc/storage.json"
eval $(udevadm info --query=property --name=$device_path | grep ID_SERIAL)  
serial=$ID_SERIAL
#serial=$(cat /sys/block/$device/serial)

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

# Execute the curl request and retrieve storages data
retry_count=0
max_retries=10
retry_delay=5

while [ $retry_count -lt $max_retries ]; do
    curl_output=$(curl -s "$storage_api_endpoint/$workspace_id/" -H "authorization: $co_token" -H "content-type: application/json")

    # Check if the response contains key and value
    if jq -e '.meta.storages | length > 0' <<< "$curl_output" >/dev/null; then
        jq -c '.meta.storages | .[]' <<< "$curl_output" | while IFS= read -r storage; do
        
            key=$(echo "$storage" | jq -r '.name' | tr ' ' '_')
            value=$(echo "$storage" | jq -r '.volume_id' | cut -c 1-20)
        
            if [ "$key" = "null" ] || [ "$value" = "null" ]; then
                echo "Key or value is 'null'. Retrying..." >> "$log_file" 2>&1
                sleep 1;
                continue
            fi
            echo "$key $value" >> "$log_file" 2>&1
            if [ "$serial" = "$value" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Disk ID matches: $key $device_path $serial" >> "$log_file" 2>&1
                echo $key
              fi
        done
        break  # Exit the loop if key and value were found
    else
        echo "Retry $((retry_count + 1)): Volume data was not found in the endpoint. Retrying in $retry_delay seconds..." >> "$log_file" 2>&1
        sleep $retry_delay
        retry_count=$((retry_count + 1))
    fi
done

if [ $retry_count -eq $max_retries ]; then
    echo "Maximum retries exceeded. Disk ID match not found."
    exit 1
fi
