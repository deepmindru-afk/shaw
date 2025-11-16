# 🚀 Quick Railway Deployment

## One-Command Setup

Run this in your terminal:

```bash
cd backend
./setup-railway.sh
```

This script will:
1. ✅ Check/install Railway CLI
2. 🔐 Login to Railway (opens browser)
3. 📦 Create new Railway project
4. 🔑 Set all environment variables from your .env file
5. 🚀 Deploy your backend
6. 🌐 Show you the deployment URL

## What You'll Need

- A Railway account (free tier available)
- Your LiveKit credentials (already in `.env`)

## After Deployment

1. **Get your Railway URL** (shown at end of script)
2. **Update iOS app** - Set environment variable in Xcode:
   ```
   API_BASE_URL=https://your-project.up.railway.app/v1
   ```

## Manual Steps (if script fails)

If the automated script doesn't work, follow these steps:

### 1. Login
```bash
railway login
```

### 2. Initialize
```bash
railway init --name ai-voice-copilot-backend
```

### 3. Set Variables
```bash
railway variables set LIVEKIT_API_KEY=APIdMjzJuD2sqxn
railway variables set LIVEKIT_API_SECRET=cHNMaqoykB6SzASgdn5ofYekt4jxSHrFBM53NHfvwWXB
railway variables set LIVEKIT_URL=wss://bunnyai-4r3cmnxl.livekit.cloud
railway variables set NODE_ENV=production
railway variables set PORT=3000
railway variables set DATABASE_PATH=/tmp/sessions.db
```

### 4. Deploy
```bash
railway up
```

### 5. Get URL
```bash
railway status
```

## Troubleshooting

**Script fails at login:**
- Make sure you have a Railway account at https://railway.app
- Try running `railway login` manually first

**Variables not set:**
- Check Railway dashboard → Variables tab
- Make sure variable names match exactly

**Deployment fails:**
- Check Railway logs in dashboard
- Verify `package.json` has correct `start` script
- Ensure all dependencies are in `package.json`

