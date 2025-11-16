# AI Voice Copilot Backend

Node.js/Express backend for the AI Voice Copilot iOS app with LiveKit integration.

## Features

- ✅ 9 REST API endpoints for session management
- ✅ SQLite database for local development
- ✅ LiveKit token generation for real-time audio
- ✅ Simple authentication
- ✅ Production-ready (Railway/Render compatible)
- ✅ Single hybrid pipeline for OpenAI Responses, Anthropic, and Gemini models with Cartesia/ElevenLabs TTS

## Quick Start

### 1. Install Dependencies

```bash
cd backend
npm install
```

### 2. Configure Environment

Create `.env` file:

```bash
cp .env.example .env
```

Edit `.env` with your LiveKit credentials:

```env
PORT=3000
LIVEKIT_API_KEY=your_api_key_here
LIVEKIT_API_SECRET=your_api_secret_here
LIVEKIT_URL=wss://your-project.livekit.cloud
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY= AIza...
CARTESIA_API_KEY=ct-...
ELEVEN_API_KEY=elevenlabs-...
PERPLEXITY_API_KEY=plx-...
```

OpenAI/Anthropic/Gemini keys power the hybrid text LLM adapters, Cartesia/ElevenLabs handle server-side TTS, and Perplexity enables the optional `web_search` function.

### 3. Start Server

```bash
npm start
```

Server runs at: **http://localhost:3000**

## Get LiveKit Credentials

1. Go to [LiveKit Cloud](https://cloud.livekit.io)
2. Sign up (free tier available)
3. Create a project
4. Copy:
   - API Key
   - API Secret
   - WebSocket URL (wss://...)

Paste into `.env` file.

## API Endpoints

All endpoints use `/v1/` prefix:

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/v1/auth/login` | Login (returns token) |
| POST | `/v1/auth/refresh` | Refresh auth token |
| POST | `/v1/sessions/start` | Start new session |
| POST | `/v1/sessions/end` | End session |
| GET | `/v1/sessions` | List user sessions |
| GET | `/v1/sessions/:id` | Get session details |
| GET | `/v1/sessions/:id/turns` | Get conversation |
| GET | `/v1/sessions/:id/summary` | Get AI summary |
| POST | `/v1/sessions/:id/turns` | Log conversation turn |
| DELETE | `/v1/sessions/:id` | Delete session |

## Connect iOS App

In Xcode, set environment variable:

```
API_BASE_URL=http://localhost:3000/v1
```

Or for production:

```
API_BASE_URL=https://your-app.railway.app/v1
```

## Deploy to Production

### Railway (Recommended)

```bash
# Install Railway CLI
npm install -g @railway/cli

# Login
railway login

# Initialize project
railway init

# Add environment variables in Railway dashboard
railway variables set LIVEKIT_API_KEY=your_key
railway variables set LIVEKIT_API_SECRET=your_secret
railway variables set LIVEKIT_URL=wss://your-project.livekit.cloud

# Deploy
git push
```

Railway auto-detects Node.js and deploys. Copy the URL.

### Render

1. Push code to GitHub
2. Create new Web Service in Render
3. Connect your repo
4. Add environment variables
5. Deploy

## Database

- **Local**: SQLite (`./data/sessions.db`)
- **Production**: Automatically uses PostgreSQL if `DATABASE_URL` env var exists (Railway/Render provide this)

## Testing

```bash
# Health check
curl http://localhost:3000/health

# Login
curl -X POST http://localhost:3000/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123"}'

# Start session (use token from login)
curl -X POST http://localhost:3000/v1/sessions/start \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"context":"phone"}'
```

## Development

Auto-reload on file changes:

```bash
npm run dev
```

## Generate Voice Previews

Voice previews are pre-generated static audio files that users can play when selecting a voice. The system automatically detects new voices and generates missing previews.

### Adding New Voices

1. **Add voice to `voice-config.json`**:
   ```json
   {
     "id": "cartesia-new-voice",
     "tts": "cartesia/sonic-3:voice-id-here",
     "provider": "cartesia",
     "name": "New Voice",
     "description": "Voice description"
   }
   ```

2. **Run the generator**:
   ```bash
   npm run generate-previews
   ```
   
   This will:
   - ✅ Detect which previews are missing
   - ✅ Generate only new voice previews automatically
   - ✅ Skip existing previews (unless using `--all` flag)

3. **Commit and deploy**:
   - Commit the new preview files
   - Deploy to Railway/production
   - Users will automatically see new voices with previews

### Manual Commands

```bash
# Generate missing previews only (default)
npm run generate-previews

# Regenerate all previews
npm run generate-previews -- --all
```

### CI/CD Integration

Add to your Railway build script or CI/CD pipeline:
```bash
npm run generate-previews
```

This ensures new voices get previews automatically on every deployment.

### File Structure

- **Config**: `backend/voice-config.json` - Single source of truth for voices
- **Previews**: `backend/public/voice-previews/` - Generated audio files
- **Served at**: `/voice-previews/{voiceId}.{ext}` - Automatically served by Express

## Troubleshooting

**"LiveKit credentials not configured"**
- Check `.env` file exists
- Verify LIVEKIT_* variables are set
- Restart server after changing .env

**"EADDRINUSE: Port 3000 already in use"**
- Change PORT in .env: `PORT=3001`
- Or kill existing process: `lsof -ti:3000 | xargs kill`

**iOS app can't connect**
- Verify server is running: `curl http://localhost:3000/health`
- Check iOS app has correct URL
- Use `http://localhost:3000/v1` (not 127.0.0.1)
