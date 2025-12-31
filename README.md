# FileS3

**FileS3** (pronounced Files Tree) is a **privacy-first, Free and Open-Source, S3-compatible cloud storage application** for **mobile and desktop**.  
It lets you use **your own S3 or S3-compatible storage** (AWS S3, MinIO, Wasabi, R2, etc.) as a secure, vendor-neutral cloud drive with sync and advanced file management.

No lock-in. No proprietary backend.  
**Your files stay in your bucket.**

## Features

- **Bring Your Own Cloud (BYOC)**
  - Works with **AWS S3 and S3-compatible providers**
  - Your credentials, your bucket, your control

- **File-centric experience**
  - Treat object storage like a real file system
  - Folders, prefixes, browsing, file management, search
  - Share files as attachments or links

- **Advanced File Management**
  - Copy, rename, move, delete
  - Works cleanly with large buckets
  - Offline access

- **Sync & Transfer**
  - Accurate sync engine with conflict resolution
  - Available transfer modes:
    - Sync mode: two-way sync between local and remote
    - Upload only mode: one-way upload from local to remote

- **User-friendly**
  - Simple setup
  - Intuitive UI
  - Responsive performance

- **Desktop + Mobile**
  - Desktop builds comming soon (Windows, macOS, Linux)
  - Same config, same behavior across devices

- **Privacy-first**
  - No FileS3 servers involved. Your data stays between you and your S3 provider
  - No telemetry, no tracking, no ads, no bloat, no data re-hosting or proxying
  - Your credentials stored locally
  - Open Source ([MIT License](LICENSE))

## Philosophy

FileS3 is built on a simple idea:

> **Your cloud is your storage — you just need a good client.**

FileS3 does **not** proxy your data, mirror it, or re-host it.  
It directly talks to your S3 endpoint using standard APIs.

---

## Supported Storage

FileS3 works with any **S3-compatible** service, including but not limited to:

- AWS S3
- MinIO
- Cloudflare R2
- Wasabi
- Backblaze B2 (S3 API)
- Any custom S3 endpoint

---

## Required S3 Permissions

Your credentials need **only these permissions**:

```json
[
  "s3:ListBucket",
  "s3:GetObject",
  "s3:PutObject",
  "s3:DeleteObject"
]
```

## Configuration

In FileS3, you’ll configure:

- Access Key
- Secret Key
- Region
- Bucket name
- Prefix (optional)
- Custom host / endpoint (optional)

This allows you to connect to any standard or self-hosted S3 service.

Example resource ARN:
```
arn:aws:s3:::your-bucket/your-prefix*
```

## Security Notes

Credentials are stored locally on your device

FileS3 does not send credentials anywhere else

- No background servers
- No account system
- No analytics

You can audit and revoke access at any time from your S3 provider.

## Tech Stack

- Flutter (desktop + mobile)
- Direct S3 REST API
- No backend services
- No vendor SDK lock-in

## Use Cases

- Personal cloud drive using your own S3 bucket
- Developer-friendly S3 browser
- Lightweight alternative to proprietary cloud storage apps
- Managing self-hosted or private object storage
- Cross-platform file sync backed by S3

## Non-Goals

FileS3 intentionally does not:

- Provide its own storage
- Act as a middleman or proxy
- Hide how S3 works
- Lock you into a proprietary format

## Roadmap (Indicative)

- Background sync
- Encryption-at-rest (client-side)
- Multiple profiles
- Read-only credentials mode
- CLI companion (for desktop)

## License

[MIT License](LICENSE)

## Name Meaning

FileS3 = Files, backed by S3

Simple, literal, and intentional.

If you use FileS3, you already understand it.
That’s the point.

## Alternatives
There are a few S3-compatible storage apps on mobile, but most are proprietary, ad-supported, and/or lack sync features. Here are some popular alternatives:

### [Owlfiles - File Manager](https://play.google.com/store/apps/details?id=com.skyjos.apps.fileexplorerfree&pcampaignid=web_share)
- Pros:
  - Feature-rich file manager with cloud storage support
  - Multiple non S3 cloud providers supported as well
- Cons:
  - Proprietary
  - Requires Full S3 access
  - Most features locked behind paywall
  - Requires account creation for most features

### [BucketAnywhere for S3](https://play.google.com/store/apps/details?id=lysesoft.s3anywhere&pcampaignid=web_share)
- Pros:
  - Feature-rich
  - Multiple profiles
  - Background sync
- Cons:
  - Proprietary
  - Ads
  - Outdated UI 
  - No desktop app
  - Many features locked behind paywall
  - Sync is one way only (requires either remote or local to be master)

### [Simple S3 Browser](https://play.google.com/store/apps/details?id=vn.com.goldtek.s3browser&pcampaignid=web_share)
- Pros:
  - Clean & lightweight UI
  - Multiple profiles
- Cons:
  - Proprietary
  - Ads/[Non-free pro version](https://play.google.com/store/apps/details?id=vn.com.goldtek.s3browserpro&pcampaignid=web_share)
  - No sync
  - No desktop app
  - Limited features

### [Cloudly - S3 Manager](https://play.google.com/store/apps/details?id=mr.onno.s3&pcampaignid=web_share)
- Pros:
  - Free and no ads
- Cons:
  - Proprietary
  - No sync
  - No desktop app
  - Limited features

### [Buffix S3 Client](https://play.google.com/store/apps/details?id=com.orbigle.buffisapp&pcampaignid=web_share)
-Cons:
  - Proprietary
  - Did not work in testing. Probable bugs and limited features.