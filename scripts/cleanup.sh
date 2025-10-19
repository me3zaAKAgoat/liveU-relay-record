#!/bin/bash
# Cleanup script - removes local recordings after successful S3 upload
# Run this as a cron job or manually to free disk space

set -euo pipefail

VOD_DIR="/vod/liveu"
MIN_AGE_HOURS="${1:-24}"  # Default: delete files older than 24 hours

echo "[$(date)] Starting cleanup of ${VOD_DIR}"
echo "[$(date)] Removing files older than ${MIN_AGE_HOURS} hours"

DELETED_COUNT=0
DELETED_SIZE=0

while IFS= read -r -d '' FILE; do
  SIZE=$(stat -f%z "$FILE" 2>/dev/null || stat -c%s "$FILE" 2>/dev/null || echo 0)
  rm -f "$FILE"
  DELETED_COUNT=$((DELETED_COUNT + 1))
  DELETED_SIZE=$((DELETED_SIZE + SIZE))
  echo "[$(date)] Deleted: $(basename "$FILE") ($(numfmt --to=iec-i --suffix=B $SIZE 2>/dev/null || echo "${SIZE} bytes"))"
done < <(find "$VOD_DIR" -type f -mmin +$((MIN_AGE_HOURS * 60)) -print0 2>/dev/null)

if [ $DELETED_COUNT -eq 0 ]; then
  echo "[$(date)] No files to delete"
else
  echo "[$(date)] Cleanup complete: ${DELETED_COUNT} files removed ($(numfmt --to=iec-i --suffix=B $DELETED_SIZE 2>/dev/null || echo "${DELETED_SIZE} bytes"))"
fi

