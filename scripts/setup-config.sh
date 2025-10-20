#!/bin/sh
set -eu

# This script ensures the config directory and forward.env file exist
# It handles both local development and Coolify deployments

CONFIG_DIR="${CONFIG_DIR:-.}/config"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Create forward.env if it doesn't exist
if [ ! -f "$CONFIG_DIR/forward.env" ]; then
  cat > "$CONFIG_DIR/forward.env" << 'EOF'
# Cloud OBS forwarding configuration
# Set these to enable forwarding to your cloud streaming endpoint

# RTMP endpoint URL (e.g., rtmp://a.rtmp.youtube.com/live2)
RTMP_URL=

# Stream key for authentication at the endpoint
STREAM_KEY=
EOF
  echo "Created $CONFIG_DIR/forward.env with defaults"
else
  echo "$CONFIG_DIR/forward.env already exists"
fi

chmod 600 "$CONFIG_DIR/forward.env"
echo "Config setup complete"
