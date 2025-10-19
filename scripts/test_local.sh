#!/bin/bash
# Local testing script - simulates LiveU stream without actual hardware

set -euo pipefail

echo "=== LiveU Relay Local Test ==="
echo ""

# Check if docker compose is running
if ! docker compose ps | grep -q "liveu-relay"; then
  echo "ERROR: Relay container not running. Start with: docker compose up -d"
  exit 1
fi

echo "Relay is running. Starting test stream..."
echo ""

# Check for test video file
TEST_VIDEO="${1:-}"
if [ -z "$TEST_VIDEO" ]; then
  echo "Usage: $0 <path-to-test-video.mp4>"
  echo ""
  echo "Example: $0 ~/Downloads/test_1080p60.mp4"
  echo ""
  echo "If you don't have a test file, create one:"
  echo "  ffmpeg -f lavfi -i testsrc=duration=300:size=1920x1080:rate=60 \\"
  echo "    -f lavfi -i sine=frequency=1000:duration=300 \\"
  echo "    -c:v libx264 -preset veryfast -b:v 12M -c:a aac -b:a 192k \\"
  echo "    test_1080p60_12mbps.mp4"
  exit 1
fi

if [ ! -f "$TEST_VIDEO" ]; then
  echo "ERROR: File not found: $TEST_VIDEO"
  exit 1
fi

echo "Using test video: $TEST_VIDEO"
echo "Press Ctrl+C to stop the stream (will trigger upload and email)"
echo ""
echo "Streaming to relay via SRT..."
echo ""

# Stream to local relay
# Add -t 120 to limit to 2 minutes for testing
ffmpeg -re -stream_loop -1 -i "$TEST_VIDEO" \
  -c copy -f mpegts "srt://127.0.0.1:8890?mode=caller&latency=120&streamid=publish:liveu"

echo ""
echo "Stream ended. Check logs for upload and email status:"
echo "  docker compose logs -f mediamtx"
echo ""
echo "Check recordings:"
echo "  ls -lh vod/liveu/"

