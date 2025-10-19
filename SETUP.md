# Quick Setup Guide

## 1. Create your environment file

```bash
cp env.example .env
nano .env
```

Fill in these values:

### DigitalOcean Spaces (for storing recordings)

- `SPACES_ACCESS_KEY` - Your DigitalOcean Spaces access key
- `SPACES_SECRET_KEY` - Your DigitalOcean Spaces secret key
- `SPACES_REGION` - DO Spaces region (e.g., `nyc3`, `sfo3`, `fra1`)
- `SPACES_BUCKET` - Your Spaces bucket name
- `SPACES_ENDPOINT` - DO Spaces endpoint (e.g., `https://nyc3.digitaloceanspaces.com`)

### SendGrid (for email notifications)

- `SENDGRID_API_KEY` - from https://app.sendgrid.com/settings/api_keys
- `SENDGRID_FROM_EMAIL` - verified sender email in SendGrid
- `RECIPIENT_EMAIL` - your client's email

## 2. Update IRLToolkit destination

Edit `mediamtx.yml` line 29:

```yaml
-f flv rtmp://IRL_TOOLKIT_HOST:1935/live/STREAM_KEY
```

Replace:

- `IRL_TOOLKIT_HOST` with IRLToolkit server IP (e.g., `192.168.1.100`)
- `STREAM_KEY` with the ingest key from IRLToolkit

## 3. Start the relay

```bash
docker compose up -d
```

## 4. Configure LiveU

**SRT (recommended):**

```
srt://YOUR_VPS_IP:7001?streamid=liveu&latency=120
```

**RTMP (alternative):**

```
rtmp://YOUR_VPS_IP:1935/liveu
```

## 5. Configure IRLToolkit

Add custom RTMP source:

```
rtmp://YOUR_VPS_IP:1935/liveu
```

## Done!

When the stream ends, your client receives an email with download links.

---

## DigitalOcean Spaces Quick Setup

1. **Create Space:**

   - Go to: https://cloud.digitalocean.com/spaces
   - Click "Create a Space"
   - Choose region (pick closest to your VPS)
   - Name your space (e.g., `my-cleanfeed-recordings`)
   - Allow file listing: No (for security)

2. **Create API Key:**

   - Go to: https://cloud.digitalocean.com/account/api/spaces
   - Click "Generate New Key"
   - Save the Access Key and Secret Key immediately
   - Note your endpoint URL (e.g., `https://nyc3.digitaloceanspaces.com`)

3. **Configure .env:**

   ```bash
   SPACES_ACCESS_KEY=your_spaces_access_key
   SPACES_SECRET_KEY=your_spaces_secret_key
   SPACES_REGION=nyc3
   SPACES_BUCKET=my-cleanfeed-recordings
   SPACES_ENDPOINT=https://nyc3.digitaloceanspaces.com
   ```

4. **Test connection:**
   ```bash
   aws s3 ls s3://my-cleanfeed-recordings --endpoint-url https://nyc3.digitaloceanspaces.com
   ```

## SendGrid Quick Setup

1. Sign up: https://sendgrid.com
2. Verify sender: Settings → Sender Authentication
3. Create API key: Settings → API Keys → Create API Key
4. Copy key to `.env`

## Testing Locally

```bash
# Make test script executable
chmod +x scripts/test_local.sh

# Run test (simulates LiveU)
./scripts/test_local.sh path/to/video.mp4
```

Press Ctrl+C to stop and trigger upload/email.

## Monitoring

```bash
# View logs
docker compose logs -f mediamtx

# Check recordings
ls -lh vod/liveu/

# API health
curl http://localhost:8889/v3/paths/list
```

## Costs (9-hour stream, 1080p60 @ 12 Mbps)

- Storage: ~$1.12/month (48.6 GB)
- Download: ~$4.37 per full download
- Email: $0 (free tier)
- Total: ~$5–6 per stream
