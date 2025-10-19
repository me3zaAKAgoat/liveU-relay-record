# Production Deployment Checklist

## Pre-Deployment

### 1. VPS Selection

Choose based on expected quality:

**1080p60 @ 12 Mbps:**

- Provider: DigitalOcean, Hetzner, Vultr, Linode
- Spec: 2 vCPU, 2 GB RAM, 200 GB SSD
- Network: 1 Gbps, 3–5 TB/month transfer
- Cost: ~$12–18/month

**4K60 @ 50 Mbps:**

- Provider: Hetzner (best value), OVH
- Spec: 4 vCPU, 8 GB RAM, 1 TB SSD
- Network: 1 Gbps unmetered or 10+ TB/month
- Cost: ~$35–50/month

### 2. Domain & DNS (optional but recommended)

```bash
# Point a subdomain to your VPS
relay.yourdomain.com -> VPS_IP
```

### 3. DigitalOcean Spaces Setup

1. **Create Space:**

   - Go to: https://cloud.digitalocean.com/spaces
   - Create new Space (choose region close to your VPS)
   - Name: `your-cleanfeed-bucket`
   - Disable file listing for security

2. **Create API Key:**

   - Go to: https://cloud.digitalocean.com/account/api/spaces
   - Generate new key (save Access Key and Secret immediately)
   - Note endpoint URL (e.g., `https://nyc3.digitaloceanspaces.com`)

3. **Test connection:**
   ```bash
   aws s3 ls s3://your-cleanfeed-bucket --endpoint-url https://nyc3.digitaloceanspaces.com
   ```

### 4. SendGrid Setup

1. Sign up: https://sendgrid.com/pricing (Free: 100 emails/day)
2. Single Sender Verification:
   - Settings → Sender Authentication
   - Add and verify your "From" email
3. Create API Key:
   - Settings → API Keys
   - Create API Key (Full Access or Mail Send only)
   - Copy immediately (shown once)

---

## Deployment Steps

### 1. Initial Server Setup

```bash
# SSH into VPS
ssh root@YOUR_VPS_IP

# Update system
apt update && apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Install Docker Compose
apt install docker-compose-plugin -y

# Create project directory
mkdir -p /opt/liveu-relay
cd /opt/liveu-relay
```

### 2. Upload Project Files

From your local machine:

```bash
# Copy project to VPS
scp -r /Users/me3za/projectLiveUVOD/* root@YOUR_VPS_IP:/opt/liveu-relay/

# Or use git
cd /opt/liveu-relay
git clone YOUR_REPO_URL .
```

### 3. Configure Environment

```bash
cd /opt/liveu-relay

# Create .env from template
cp env.example .env
nano .env
```

Fill in ALL values:

- AWS credentials and bucket name
- SendGrid API key and verified sender email
- Client recipient email

### 4. Configure IRLToolkit Forwarding

```bash
nano mediamtx.yml
```

Line 29, replace:

```yaml
-f flv rtmp://IRL_TOOLKIT_HOST:1935/live/STREAM_KEY
```

With actual IRLToolkit host IP and stream key.

### 5. Firewall Configuration

```bash
# Install UFW (if not present)
apt install ufw -y

# Allow SSH (IMPORTANT: do this first!)
ufw allow 22/tcp

# Allow relay ports
ufw allow 1935/tcp   # RTMP
ufw allow 7001/udp   # SRT
ufw allow 8889/tcp   # API (optional, for monitoring)

# Enable firewall
ufw enable
ufw status
```

### 6. Start Services

```bash
cd /opt/liveu-relay

# Pull images
docker compose pull

# Start in foreground to check for errors
docker compose up

# If no errors, stop with Ctrl+C and start in background
docker compose up -d

# Check status
docker compose ps
docker compose logs -f mediamtx
```

### 7. Verify Deployment

```bash
# Check container is running
docker compose ps
# Should show: liveu-relay   Up

# Check API
curl http://localhost:8889/v3/paths/list
# Should return JSON

# Check recordings directory exists
ls -la vod/
mkdir -p vod/liveu
```

---

## Configure Encoder & IRLToolkit

### LiveU Configuration

**Option A: SRT (recommended for cellular)**

```
URL: srt://YOUR_VPS_IP:7001?streamid=liveu&latency=120
Mode: Caller
Encryption: Optional (add &passphrase=yourpass)
```

**Option B: RTMP**

```
URL: rtmp://YOUR_VPS_IP/liveu
```

Set video/audio codec:

- Video: H.264 (or H.265 if IRLToolkit supports it)
- Audio: AAC, 48 kHz
- Bitrate: 8–12 Mbps (1080p60) or 25–60 Mbps (4K60)

### IRLToolkit Configuration

Add custom RTMP input:

```
rtmp://YOUR_VPS_IP:1935/liveu
```

Or if you configured push in `mediamtx.yml`, IRLToolkit will automatically receive the stream.

---

## Testing

### 1. Test Stream (without LiveU)

From your local machine:

```bash
# Stream a test file to relay
ffmpeg -re -stream_loop 5 -i test_1080p60.mp4 \
  -c copy -f mpegts "srt://YOUR_VPS_IP:7001?mode=caller&latency=120&streamid=liveu"
```

### 2. Verify Recording

On VPS:

```bash
# Check files are being created
watch -n 2 ls -lh /opt/liveu-relay/vod/liveu/

# Check one file is valid
ffprobe /opt/liveu-relay/vod/liveu/FILENAME.mp4
```

### 3. Verify Forwarding to IRLToolkit

In IRLToolkit, check preview/input shows the stream.

### 4. Test End-of-Stream

Stop the ffmpeg test stream (Ctrl+C). Within 1–2 minutes:

1. Check logs: `docker compose logs -f mediamtx`
2. Verify S3 upload: `aws s3 ls s3://your-cleanfeed-bucket/cleanfeed/`
3. Check email was sent (check spam folder)

---

## Post-Deployment

### 1. Set Up Automated Cleanup

```bash
# Add cron job to clean old local files
crontab -e
```

Add:

```cron
# Clean local recordings older than 24 hours (daily at 4 AM)
0 4 * * * /opt/liveu-relay/scripts/cleanup.sh 24 >> /var/log/cleanfeed-cleanup.log 2>&1
```

### 2. Monitoring (optional)

Install simple uptime monitor:

```bash
# Add to crontab
*/5 * * * * curl -sf http://localhost:8889/v3/paths/list > /dev/null || echo "Relay down" | mail -s "Alert: Relay Down" admin@example.com
```

Or use external monitoring: UptimeRobot, Healthchecks.io, etc.

### 3. Spaces Lifecycle Policy (optional cost optimization)

DigitalOcean Spaces doesn't support S3-style lifecycle policies, but you can manually manage storage:

```bash
# Optional: delete files older than 30 days
find /opt/liveu-relay/vod -type f -mtime +30 -delete

# Or use a cron job for automated cleanup
```

---

## Troubleshooting

### Container won't start

```bash
docker compose logs mediamtx
# Check for missing env vars or permission errors
```

### LiveU can't connect

```bash
# Check firewall
ufw status

# Check if port is listening
ss -tulnp | grep 7001
ss -tulnp | grep 1935

# Test from another machine
ffprobe srt://YOUR_VPS_IP:7001?mode=caller
```

### Recording not starting

```bash
# Check permissions
ls -la /opt/liveu-relay/vod
chmod -R 755 /opt/liveu-relay/vod

# Check disk space
df -h
```

### Email not sent

```bash
# Verify SendGrid API key
curl --request POST \
  --url https://api.sendgrid.com/v3/mail/send \
  --header "Authorization: Bearer YOUR_SENDGRID_KEY" \
  --header "Content-Type: application/json" \
  --data '{"personalizations":[{"to":[{"email":"test@example.com"}]}],"from":{"email":"YOUR_FROM_EMAIL"},"subject":"Test","content":[{"type":"text/plain","value":"Test"}]}'

# Should return HTTP 202
```

### Spaces upload fails

```bash
# Test Spaces credentials
docker compose exec mediamtx aws s3 ls s3://your-cleanfeed-bucket/ --endpoint-url https://nyc3.digitaloceanspaces.com

# Check if API key has proper permissions in DigitalOcean dashboard
```

---

## Maintenance

### View Logs

```bash
docker compose logs -f mediamtx
```

### Restart Service

```bash
docker compose restart
```

### Update mediaMTX

```bash
docker compose pull
docker compose up -d
```

### Backup Configuration

```bash
tar -czf liveu-relay-backup-$(date +%F).tar.gz \
  docker-compose.yml mediamtx.yml .env scripts/
```

---

## Security Hardening

### 1. Add SRT Passphrase

In LiveU config:

```
srt://YOUR_VPS_IP:7001?streamid=liveu&passphrase=STRONG_RANDOM_PASS
```

In `mediamtx.yml`, add under `paths.liveu`:

```yaml
srtPublishPassphrase: STRONG_RANDOM_PASS
```

### 2. Restrict SSH

```bash
# Disable root login
nano /etc/ssh/sshd_config
# Set: PermitRootLogin no

# Use SSH keys only
# Set: PasswordAuthentication no

systemctl restart sshd
```

### 3. Fail2Ban

```bash
apt install fail2ban -y
systemctl enable fail2ban
systemctl start fail2ban
```

### 4. Keep System Updated

```bash
# Enable unattended upgrades
apt install unattended-upgrades -y
dpkg-reconfigure --priority=low unattended-upgrades
```

---

## Cost Optimization

### 1. Use CloudFront for downloads

Reduces S3 egress costs significantly for multiple downloads.

### 2. Enable S3 Intelligent-Tiering

```bash
aws s3api put-bucket-intelligent-tiering-configuration \
  --bucket your-cleanfeed-bucket \
  --id AutoArchive \
  --intelligent-tiering-configuration file://intelligent-tiering.json
```

### 3. Choose region wisely

- S3 us-east-1 is cheapest
- VPS in same region as LiveU reduces latency
- Balance costs vs performance

---

## Emergency Procedures

### Disk Full

```bash
# Immediate cleanup
find /opt/liveu-relay/vod -type f -mmin +60 -delete

# Extend volume (cloud provider)
# Then resize filesystem
```

### Service Down

```bash
# Quick restart
docker compose restart

# Full reset
docker compose down
docker compose up -d
```

### Lost Credentials

Re-generate IAM keys and SendGrid API key, update `.env`, restart.

---

## Support Contacts

- mediaMTX docs: https://github.com/bluenviron/mediamtx
- AWS S3 support: https://console.aws.amazon.com/support
- SendGrid support: https://support.sendgrid.com/
- FFmpeg docs: https://ffmpeg.org/documentation.html
