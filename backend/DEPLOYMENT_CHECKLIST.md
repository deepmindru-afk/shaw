# LiveKit Agent Deployment Checklist

## Problem Diagnosed

Your iOS app **successfully connects to LiveKit**, but calls don't work because:

### ❌ **The Python agent isn't running**

**Evidence:**
```
Room.connect(url:token:) Connecting to room...  ✅
Room.signalClient didReceiveConnectResponse     ✅
SignalClient._sendRequest() connectionState is .disconnected  ❌
```

The room connects, but there's **no agent participant** to handle the voice conversation.

---

## Root Cause

Railway's previous config used background processes (`&`):
```json
"startCommand": "npm start & python agent.py start"
```

**Problem**: Background processes fail silently on Railway. The agent crashes but deployment shows "success."

---

## Fixes Deployed

### 1. ✅ Multi-Process Startup Script
**File**: `start.sh`
- Runs both Node.js server + Python agent
- Monitors both processes
- Exits if either process fails

### 2. ✅ Agent Health Endpoint
**File**: `server.js` - New endpoint: `GET /health/agent`
```json
{
  "agent_configured": true,
  "livekit_url": "wss://bunnyai-4r3cmnxl.livekit.cloud",
  "timestamp": "2025-11-10T23:55:00.000Z"
}
```

### 3. ✅ Railway Config Update
**File**: `railway.json`
```json
"startCommand": "./start.sh"
```

---

## Deployment Steps

### Step 1: Verify Git Push
```bash
git log -1 --oneline
# Should show: "Fix LiveKit agent deployment on Railway"
```

### Step 2: Trigger Railway Deployment

Railway auto-deploys on git push, but you can also:

1. **Via CLI**:
   ```bash
   cd backend
   railway up
   ```

2. **Via Dashboard**:
   - https://railway.app/project/547fff28-a168-4fdb-9b84-cb9710ff0f15
   - Click "Deploy" > "Redeploy"

3. **Via API** (if you have token):
   ```bash
   curl -X POST https://backboard.railway.com/graphql/v2 \
     -H "Authorization: Bearer $RAILWAY_TOKEN" \
     -d '{"query":"mutation { serviceInstanceRedeploy(...) }"}'
   ```

### Step 3: Monitor Deployment (5-10 minutes)

**Watch deployment logs:**
```bash
railway logs --follow
```

**Look for these success indicators:**
```
✅ Loaded .env file successfully
✅ LiveKit configuration is valid
🚀 Starting multi-process deployment...
🤖 Starting LiveKit agent...
✅ Agent started (PID: ...)
🌐 Starting Node.js server...
✅ Server started (PID: ...)
🚀 Server running on http://localhost:3000
```

### Step 4: Verify Deployment

**Test health endpoints:**
```bash
# Main health check
curl https://ai-voice-copilot-backend-production.up.railway.app/health

# Agent health check (NEW - should work after deployment)
curl https://ai-voice-copilot-backend-production.up.railway.app/health/agent
```

**Expected response:**
```json
{
  "agent_configured": true,
  "livekit_url": "wss://bunnyai-4r3cmnxl.livekit.cloud",
  "timestamp": "2025-11-10T..."
}
```

---

## Testing Call Flow

### 1. Test From iOS App

**Launch app and initiate call:**
```
✅ Authentication succeeds
✅ Session starts (gets LiveKit token)
✅ Room connects
✅ Agent joins room automatically  ← This should now work!
✅ Greeting plays: "Hello, how can I help you?"
```

**Watch Xcode console for:**
```
Room.connect(url:token:) Connecting to room...
Room.signalClient didReceiveConnectResponse ServerInfo(...)
Room participant joined: agent-...  ← NEW!
Room didSubscribeTo audio track  ← NEW!
```

### 2. Local Testing (Optional)

**Test agent locally before deploying:**
```bash
cd backend
./test-local.sh
```

This runs:
- Node.js server on `localhost:3000`
- Python agent connected to LiveKit cloud
- Both processes monitored

**Test via LiveKit Console:**
```bash
source venv/bin/activate
python agent.py console
```

This opens an interactive chat to test the agent.

---

## Troubleshooting

### Issue: Deployment succeeds but `/health/agent` returns 404

**Cause**: Old deployment still running

**Fix**:
```bash
railway service  # Link to service
railway redeploy  # Force redeploy
```

### Issue: Agent crashes with "No module named 'livekit'"

**Cause**: Railway didn't install Python dependencies

**Fix**: Check `railway.json` build command:
```json
"buildCommand": "npm install && pip install -r requirements.txt"
```

### Issue: Agent crashes with "LiveKit API key not set"

**Cause**: Environment variables not configured on Railway

**Fix**: Set in Railway dashboard:
```bash
LIVEKIT_API_KEY=APIdMjzJuD2sqxn
LIVEKIT_API_SECRET=cHNMaqoykB6SzASgdn5ofYekt4jxSHrFBM53NHfvwWXB
LIVEKIT_URL=wss://bunnyai-4r3cmnxl.livekit.cloud
OPENAI_API_KEY=sk-proj-...
```

### Issue: iOS app still shows "disconnected" after connecting

**Cause**: Agent not joining rooms

**Check Railway logs:**
```bash
railway logs | grep "Agent joining room"
```

Should see: `🎙️ Agent joining room: <room-name>` for each call.

---

## Next Steps

1. **Wait for deployment** (check Railway dashboard)
2. **Verify** `/health/agent` endpoint returns 200
3. **Test call** from iOS app
4. **Monitor logs** during first test call
5. **Verify** agent greeting plays

---

## Success Criteria

✅ Server health check returns 200
✅ Agent health check returns `agent_configured: true`
✅ iOS app connects and hears agent greeting
✅ Two-way audio conversation works
✅ Session logs appear in backend database

---

## Files Changed

```
backend/
├── railway.json       ← Updated startCommand
├── start.sh           ← NEW: Multi-process launcher
├── server.js          ← NEW: /health/agent endpoint
└── test-local.sh      ← NEW: Local testing helper
```

**Commit**: `79cac82` - "Fix LiveKit agent deployment on Railway"
