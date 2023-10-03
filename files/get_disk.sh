#!/bin/bash
device=$1
device_path=/dev/$1

log_file="/var/log/disk_mounting.log"

serial=$(cat /sys/block/$device/serial)

# Read storage data from JSON file
workspace_file="/etc/rsc/storage.json"
workspace_data=$(cat "$workspace_file")

# Parse storage data to get required values
co_token=$(echo "$workspace_data" | jq -r '.co_token')
workspace_id=$(echo "$workspace_data" | jq -r '.workspace_id')
storage_api_endpoint=$(echo "$workspace_data" | jq -r '.storage_api_endpoint')

# Execute the curl request and retrieve storages data
## URL should be read from workspace.json, hard coded for testing.
curl "$storage_api_endpoint/$workspace_id/" \
  -H "authorization: $co_token" -H "content-type: application/json" |
  jq -c ".meta.storages" | jq -c '.[]' | while IFS= read -r storage; do
  key=$(echo "$storage" | jq -r '.name' | tr ' ' '_')
  value=$(echo "$storage" | jq -r '.volume_id' | cut -c 1-20)
  echo "$key $value" >> "$log_file" 2>&1

if [ "$serial" = "$value" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Disk ID matches: $key $device_path $serial" >> "$log_file" 2>&1
    /opt/mount_disks.sh "$key" "$device_path" >> "$log_file" 2>&1
  # else
  #   echo "Serial number does not match: $serial" >> "$log_file" 2>&1
  fi
done
