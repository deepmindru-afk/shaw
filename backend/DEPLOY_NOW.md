# 🚀 Deploy to Railway - Run This Now!

## Single Command Deployment

**Open your terminal and run:**

```bash
cd /Users/jeremycai/Projects/carplay-swiftui-master/backend && ./setup-railway.sh
```

This will:
1. ✅ Verify Railway CLI is installed
2. 🔐 **Open browser for Railway login** (you'll need to authenticate)
3. 📦 Create Railway project automatically
4. 🔑 Set all environment variables from your .env
5. 🚀 Deploy your backend
6. 🌐 Show you the deployment URL

## What Happens

1. **Login**: Browser opens → Click "Authorize" → Return to terminal
2. **Project Creation**: Creates `ai-voice-copilot-backend` project
3. **Variables**: Automatically reads from `.env` and sets them
4. **Deploy**: Uploads and deploys your code
5. **Done**: Shows your live URL

## After Deployment

You'll get a URL like: `https://ai-voice-copilot-backend.up.railway.app`

**Update your iOS app:**
- In Xcode → Edit Scheme → Run → Arguments → Environment Variables
- Add: `API_BASE_URL` = `https://your-project.up.railway.app/v1`

Or update `Configuration.swift` production case with your Railway URL.

## Need Help?

If the script fails at any step, check `RAILWAY_SETUP.md` for manual instructions.

