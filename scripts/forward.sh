#!/bin/sh
set -eu

# Load forwarding config
if [ -f /config/forward.env ]; then
  . /config/forward.env
fi

RTMP_URL=${RTMP_URL:-}
STREAM_KEY=${STREAM_KEY:-}

if [ -z "$RTMP_URL" ]; then
  echo "[forward.sh] RTMP_URL not set; skipping forward"
  exit 0
fi

# Get path name from environment (MediaMTX may provide this, fallback to 'liveu')
PATH_NAME=${MTX_PATH:-liveu}

# Get ingest key for internal authentication
INGEST_KEY=${MTX_INGEST_KEY:-}

# Construct RTSP source URL with authentication
if [ -n "$INGEST_KEY" ]; then
  RTSP_URL="rtsp://liveu:${INGEST_KEY}@localhost:8554/${PATH_NAME}"
else
  RTSP_URL="rtsp://localhost:8554/${PATH_NAME}"
fi

# Construct destination URL
DEST="$RTMP_URL"
if [ -n "$STREAM_KEY" ]; then
  DEST="$RTMP_URL/$STREAM_KEY"
fi

echo "[forward.sh] Available env vars: MTX_PATH=${MTX_PATH:-unset}"
echo "[forward.sh] Forwarding from $RTSP_URL to $DEST"
exec ffmpeg -nostdin -loglevel warning -rtsp_transport tcp -i "$RTSP_URL" -map 0 -c copy -f flv "$DEST"

