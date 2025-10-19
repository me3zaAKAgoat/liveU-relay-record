#!/bin/bash
set -euo pipefail

# End-of-stream handler: uploads segments to DigitalOcean Spaces and sends email via SendGrid
# Called by mediaMTX when a stream disconnects

PATH_NAME="${1:-liveu}"
BUCKET="${SPACES_BUCKET}"
REGION="${AWS_DEFAULT_REGION:-nyc3}"
ENDPOINT="${SPACES_ENDPOINT}"
RECIPIENT="${RECIPIENT_EMAIL}"
SENDER="${SENDGRID_FROM_EMAIL}"
SENDGRID_KEY="${SENDGRID_API_KEY}"

# Date for S3 prefix
TODAY=$(date +%Y/%m/%d)
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S %Z")

echo "[$(date)] Stream ended for path: ${PATH_NAME}"

# Wait a moment for recording to finalize
sleep 2

# Find all segment files modified in the last 10 minutes (covers current session only)
# This avoids checking old files that might have been uploaded already
echo "[$(date)] Looking for recent files in /vod/${PATH_NAME}"
ALL_FILES=$(find /vod/${PATH_NAME} -type f -mmin -10 2>/dev/null | sort)

# If no recent files, also check files from the last 2 hours as fallback for longer sessions
if [ -z "$ALL_FILES" ]; then
  echo "[$(date)] No recent files, checking last 2 hours as fallback"
  ALL_FILES=$(find /vod/${PATH_NAME} -type f -mmin -120 2>/dev/null | sort)
fi

if [ -z "$ALL_FILES" ]; then
  echo "[$(date)] No files found to upload"
  echo "[$(date)] Directory contents:"
  ls -la /vod/${PATH_NAME}/ 2>/dev/null || echo "[$(date)] Directory does not exist"
  exit 0
fi

# Filter out files that already exist in S3 to prevent duplicate uploads
FILES=""
UPLOAD_COUNT=0
SKIP_COUNT=0

for FILE_PATH in $ALL_FILES; do
  BASENAME=$(basename "$FILE_PATH")
  
  # Extract date from filename (format: YYYY-MM-DD_HH-MM-SS.mp4)
  if [[ $BASENAME =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})_ ]]; then
    FILE_DATE=$(echo "$BASENAME" | grep -o '^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}')
    FILE_DATE_FORMATTED=$(echo "$FILE_DATE" | tr '-' '/')
    S3_KEY="cleanfeed/${PATH_NAME}/${FILE_DATE_FORMATTED}/${BASENAME}"
  else
    # Fallback to today's date for files without standard naming
    S3_KEY="cleanfeed/${PATH_NAME}/${TODAY}/${BASENAME}"
  fi
  
  # Check if file already exists in S3 (using noop to avoid file access)
  if aws s3 ls "s3://${BUCKET}/${S3_KEY}" --region "$REGION" --endpoint-url "$ENDPOINT" >/dev/null 2>&1; then
    echo "[$(date)] Skipping ${BASENAME} - already uploaded to S3"
    SKIP_COUNT=$((SKIP_COUNT + 1))
  else
    FILES="${FILES}${FILE_PATH}\n"
    UPLOAD_COUNT=$((UPLOAD_COUNT + 1))
  fi
done

FILES=$(echo -e "$FILES" | grep -v '^$')

if [ -z "$FILES" ]; then
  echo "[$(date)] All files already uploaded (${SKIP_COUNT} files checked)"
  exit 0
fi

echo "[$(date)] Found $(echo "$UPLOAD_COUNT") new file(s) to upload (${SKIP_COUNT} already exist in S3)"

# Upload to S3 and collect presigned URLs
LINKS=""
FILE_COUNT=0

for FILE_PATH in $FILES; do
  BASENAME=$(basename "$FILE_PATH")
  
  # Extract date from filename (format: YYYY-MM-DD_HH-MM-SS.mp4)
  if [[ $BASENAME =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})_ ]]; then
    FILE_DATE=$(echo "$BASENAME" | grep -o '^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}')
    FILE_DATE_FORMATTED=$(echo "$FILE_DATE" | tr '-' '/')
    S3_KEY="cleanfeed/${PATH_NAME}/${FILE_DATE_FORMATTED}/${BASENAME}"
  else
    # Fallback to today's date for files without standard naming
    S3_KEY="cleanfeed/${PATH_NAME}/${TODAY}/${BASENAME}"
  fi
  
  echo "[$(date)] Uploading: ${BASENAME}"
  
  if aws s3 cp "$FILE_PATH" "s3://${BUCKET}/${S3_KEY}" --region "$REGION" --endpoint-url "$ENDPOINT" --only-show-errors; then
    # Generate presigned URL (expires in 7 days)
    PRESIGNED_URL=$(aws s3 presign "s3://${BUCKET}/${S3_KEY}" --expires-in 604800 --region "$REGION" --endpoint-url "$ENDPOINT")
    LINKS="${LINKS}${BASENAME}: ${PRESIGNED_URL}\n"
    FILE_COUNT=$((FILE_COUNT + 1))
  else
    echo "[$(date)] Failed to upload: ${BASENAME}"
  fi
done

if [ $FILE_COUNT -eq 0 ]; then
  echo "[$(date)] No files uploaded successfully"
  exit 1
fi

echo "[$(date)] Successfully uploaded ${FILE_COUNT} file(s)"

# Prepare email content
EMAIL_SUBJECT="Your cleanfeed recording is ready (${TODAY})"

# Build email body with actual newlines
EMAIL_BODY="Stream ended at ${TIMESTAMP}

Your high-quality cleanfeed recordings are ready for download.

Total segments: ${FILE_COUNT}

Download links (valid for 7 days):

$(echo -e "${LINKS}")

Note: These are hourly segment files. Download all segments for the complete recording."

# Send email via SendGrid API
echo "[$(date)] Sending email to ${RECIPIENT}"

# Escape the email body for JSON (replace newlines with \n, escape quotes and backslashes)
EMAIL_BODY_ESCAPED=$(echo "$EMAIL_BODY" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')

SENDGRID_PAYLOAD=$(cat <<EOF
{
  "personalizations": [{
    "to": [{"email": "${RECIPIENT}"}]
  }],
  "from": {"email": "${SENDER}"},
  "subject": "${EMAIL_SUBJECT}",
  "content": [{
    "type": "text/plain",
    "value": "${EMAIL_BODY_ESCAPED}"
  }]
}
EOF
)

# Debug: Save payload for inspection
echo "$SENDGRID_PAYLOAD" > /tmp/sendgrid_payload.json

HTTP_CODE=$(curl -s -o /tmp/sendgrid_response.txt -w "%{http_code}" \
  --request POST \
  --url https://api.sendgrid.com/v3/mail/send \
  --header "Authorization: Bearer ${SENDGRID_KEY}" \
  --header "Content-Type: application/json" \
  --data "$SENDGRID_PAYLOAD")

if [ "$HTTP_CODE" -eq 202 ]; then
  echo "[$(date)] Email sent successfully"
else
  echo "[$(date)] Email failed with HTTP ${HTTP_CODE}"
  echo "[$(date)] SendGrid response:"
  cat /tmp/sendgrid_response.txt
  echo ""
  echo "[$(date)] Payload sent (first 500 chars):"
  head -c 500 /tmp/sendgrid_payload.json
  exit 1
fi

echo "[$(date)] Stream end processing complete"

