#!/bin/bash

bucket=$1
profile=${2:-awide}

set -e

if [ -z "$bucket" ]; then
    echo "Usage: $0 <bucket-name> [profile] "
    exit 1
fi

echo "Emptying bucket: $bucket"

# Remove all current objects (handles non-versioned and suspended-versioning buckets)
aws --profile "$profile" s3 rm "s3://$bucket" --recursive

# Remove any remaining object versions and delete markers in batches of 1000
while true; do
    raw=$(aws --profile "$profile" s3api list-object-versions \
        --bucket "$bucket" --output json 2>/dev/null)

    objects=$(echo "$raw" | jq -c '{
        Objects: ([(.Versions // [])[], (.DeleteMarkers // [])[]] | map({Key: .Key, VersionId: .VersionId})),
        Quiet: true
    }')
    count=$(echo "$objects" | jq '.Objects | length')

    [ "$count" -eq 0 ] && break

    echo "Deleting $count versions/markers..."
    aws --profile "$profile" s3api delete-objects \
        --bucket "$bucket" \
        --delete "$objects"
done

echo "Deleting bucket: $bucket"
aws --profile "$profile" s3api delete-bucket --bucket "$bucket"
echo "Done: s3://$bucket deleted"


