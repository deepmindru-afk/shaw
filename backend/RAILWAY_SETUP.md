# Railway Deployment Guide

## Quick Setup

### 1. Install Railway CLI

```bash
npm install -g @railway/cli
```

### 2. Login to Railway

```bash
railway login
```

This will open your browser to authenticate.

### 3. Initialize Railway Project

```bash
cd backend
railway init
```

When prompted:
- **Create a new project**: Yes
- **Project name**: `ai-voice-copilot-backend` (or your preferred name)
- **Environment**: `production` (or `development` for testing)

### 4. Set Environment Variables

You need to set these in Railway dashboard or via CLI:

**Via Railway Dashboard (Recommended):**
1. Go to https://railway.app
2. Select your project
3. Click on your service
4. Go to "Variables" tab
5. Add these variables:

```
LIVEKIT_API_KEY=your_api_key_here
LIVEKIT_API_SECRET=your_api_secret_here
LIVEKIT_URL=wss://bunnyai-4r3cmnxl.livekit.cloud
PORT=3000
NODE_ENV=production
DATABASE_PATH=/tmp/sessions.db
```

**Via CLI:**
```bash
railway variables set LIVEKIT_API_KEY=your_api_key_here
railway variables set LIVEKIT_API_SECRET=your_api_secret_here
railway variables set LIVEKIT_URL=wss://bunnyai-4r3cmnxl.livekit.cloud
railway variables set PORT=3000
railway variables set NODE_ENV=production
railway variables set DATABASE_PATH=/tmp/sessions.db
```

### 5. Deploy

**Option A: Deploy from Git (Recommended)**
1. Push your code to GitHub
2. In Railway dashboard, connect your GitHub repo
3. Railway will auto-deploy on push

**Option B: Deploy via CLI**
```bash
railway up
```

### 6. Get Your Backend URL

After deployment, Railway will provide a URL like:
```
https://your-project.up.railway.app
```

Your API will be available at:
```
https://your-project.up.railway.app/v1
```

### 7. Update iOS App Configuration

In Xcode, set the environment variable:
```
API_BASE_URL=https://your-project.up.railway.app/v1
```

Or update `Configuration.swift` for production:
```swift
case .production:
    return "https://your-project.up.railway.app/v1"
```

## Verification

1. Check deployment logs in Railway dashboard
2. Test health endpoint:
   ```bash
   curl https://your-project.up.railway.app/health
   ```
3. Should return: `{"status":"ok","timestamp":"..."}`

## Troubleshooting

**Build fails:**
- Check Railway logs in dashboard
- Ensure `package.json` has correct `start` script
- Verify Node.js version (Railway auto-detects)

**Environment variables not working:**
- Check Railway Variables tab
- Restart deployment after adding variables
- Verify variable names match exactly (case-sensitive)

**Database issues:**
- Railway uses ephemeral storage by default
- For production, consider Railway PostgreSQL addon
- Or use external database service

## Next Steps

1. Set up custom domain (optional) in Railway dashboard
2. Enable monitoring and alerts
3. Set up staging environment for testing
4. Configure auto-deploy from main branch

