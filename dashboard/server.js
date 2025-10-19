import express from "express";
import fs from "fs";
import path from "path";
import basicAuth from "basic-auth";
import pkg from "aws-sdk";
import dotenv from "dotenv";

// Load environment variables from .env file if it exists (for local development)
// In Docker, environment variables are passed directly by docker-compose
dotenv.config({ silent: true });

// Validate required environment variables immediately
const REQUIRED_ENV_VARS = [
  "DASH_USER",
  "DASH_PASS",
  "SPACES_ACCESS_KEY",
  "SPACES_SECRET_KEY",
  "SPACES_REGION",
  "SPACES_BUCKET",
  "SPACES_ENDPOINT",
];

const missing = REQUIRED_ENV_VARS.filter((varName) => !process.env[varName]);
if (missing.length > 0) {
  console.error("FATAL: Missing required environment variables:", missing);
  console.error(
    "Available environment variables:",
    Object.keys(process.env).sort()
  );
  process.exit(1);
}

const { S3 } = pkg;

const app = express();
app.set("view engine", "ejs");
app.set("views", path.join(process.cwd(), "views"));
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(process.cwd(), "public")));

// Auth middleware (single user) - NO FALLBACKS
const USER = process.env.DASH_USER;
const PASS = process.env.DASH_PASS;

app.use((req, res, next) => {
  const creds = basicAuth(req);
  if (!creds || creds.name !== USER || creds.pass !== PASS) {
    res.set("WWW-Authenticate", 'Basic realm="Cleanfeed Dashboard"');
    return res.status(401).send("Authentication required");
  }
  next();
});

// Spaces client
const s3 = new S3({
  accessKeyId: process.env.SPACES_ACCESS_KEY,
  secretAccessKey: process.env.SPACES_SECRET_KEY,
  endpoint: process.env.SPACES_ENDPOINT,
  region: process.env.SPACES_REGION,
  s3ForcePathStyle: true,
  signatureVersion: "v4",
});
const BUCKET = process.env.SPACES_BUCKET;

const forwardEnvPath = path.join(process.cwd(), "config", "forward.env");

function readForwardEnv() {
  const out = { RTMP_URL: "", STREAM_KEY: "" };
  if (!fs.existsSync(forwardEnvPath)) return out;
  const raw = fs.readFileSync(forwardEnvPath, "utf8");
  raw.split("\n").forEach((line) => {
    const m = line.match(/^([A-Z_]+)=(.*)$/);
    if (m) out[m[1]] = m[2];
  });
  return out;
}

function writeForwardEnv({ RTMP_URL, STREAM_KEY }) {
  const body = `RTMP_URL=${RTMP_URL || ""}\nSTREAM_KEY=${STREAM_KEY || ""}\n`;
  fs.writeFileSync(forwardEnvPath, body, "utf8");
}

function formatFileSize(bytes) {
  if (!bytes) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i];
}

app.get("/", async (req, res) => {
  const cfg = readForwardEnv();
  // list latest 100 objects under cleanfeed/
  let items = [];
  try {
    const data = await s3
      .listObjectsV2({ Bucket: BUCKET, Prefix: "cleanfeed/", MaxKeys: 100 })
      .promise();
    const sorted = (data.Contents || []).sort(
      (a, b) => new Date(b.LastModified) - new Date(a.LastModified)
    );
    // Pre-generate presigned URLs so links are absolute (no /presign hop)
    items = sorted.map((it) => ({
      Key: it.Key,
      Size: it.Size,
      LastModified: it.LastModified,
      Url: s3.getSignedUrl("getObject", {
        Bucket: BUCKET,
        Key: it.Key,
        Expires: 3600,
      }),
    }));
  } catch (e) {
    // ignore; render empty list with error note
  }
  res.render("index", { cfg, items, bucket: BUCKET, formatFileSize });
});

app.post("/save", (req, res) => {
  const { rtmpUrl, streamKey } = req.body;
  writeForwardEnv({
    RTMP_URL: (rtmpUrl || "").trim(),
    STREAM_KEY: (streamKey || "").trim(),
  });
  res.redirect("/");
});

app.get("/presign", async (req, res) => {
  const key = req.query.key;
  if (!key) return res.status(400).send("missing key");
  const url = s3.getSignedUrl("getObject", {
    Bucket: BUCKET,
    Key: key,
    Expires: 3600,
  });
  res.redirect(url);
});

const PORT = process.env.DASH_PORT || process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Dashboard on :${PORT}`));
