# Agent Join Issue - Deep Dive & Fix

## Critical Findings

### 1. **Agent Was Using OpenAI Realtime Instead of LiveKit Inference** ❌

**Problem:**
- Hybrid mode was using `openai.realtime.RealtimeModel` with `modalities=["text"]`
- This is NOT LiveKit Inference - it's using OpenAI's Realtime API directly
- User wanted LiveKit Inference (MCP) for LLM + TTS

**Fix:**
- Changed to use LiveKit Inference LLM: `llm="openai/gpt-5-mini"` (string descriptor)
- LiveKit Inference automatically handles the connection
- TTS already correct: `tts="cartesia/sonic-3:..."` or `tts="elevenlabs/..."`

**Before:**
```python
realtime_model = openai.realtime.RealtimeModel(
    temperature=0.8,
    modalities=["text"],  # Text-only output
)
agent_session = AgentSession(
    llm=realtime_model,  # ❌ OpenAI Realtime API
    tts=voice
)
```

**After:**
```python
llm_model = model or "openai/gpt-5-mini"  # ✅ LiveKit Inference
agent_session = AgentSession(
    llm=llm_model,  # ✅ LiveKit Inference LLM
    tts=voice  # ✅ LiveKit Inference TTS
)
```

### 2. **Room Auto-Creation Understanding** ✅

**Key Insight:**
- According to LiveKit docs: "The room is automatically created during dispatch if it doesn't already exist"
- We don't need to create rooms before dispatching
- Verification logic updated to handle this

**Updated Verification:**
- Now understands rooms may not exist yet (will be auto-created)
- Better logging when room doesn't exist yet

### 3. **Agent Worker Registration** ⚠️

**Critical Issue:**
- Agent worker MUST be running and registered with LiveKit Cloud
- If worker isn't running, dispatch succeeds but agent never joins
- No way to verify worker registration via API (must check logs)

**Agent Name Consistency:**
- `agent.py` uses `agent_name="agent"` (or from `LIVEKIT_AGENT_NAME` env var)
- `livekit.js` dispatches to `'agent'`
- These MUST match for explicit dispatch to work

**Added:**
- Configurable agent name via `LIVEKIT_AGENT_NAME` env var
- Better logging of agent name on startup
- Health check endpoint shows expected agent name

### 4. **Better Logging & Diagnostics** ✅

**Added:**
- Agent entrypoint logs room name, SID, job ID, and metadata
- Agent name logging on worker startup
- Health check shows agent worker info
- Verification logs understand room auto-creation

## Why Agent Wasn't Joining

Based on the investigation, the most likely reasons:

1. **Agent worker not running** - Python process crashed or never started
2. **Agent worker not registered** - Worker started but didn't connect to LiveKit Cloud
3. **Agent name mismatch** - Dispatch name didn't match worker name (unlikely, both use "agent")
4. **Wrong model configuration** - Using OpenAI Realtime instead of LiveKit Inference (now fixed)

## How to Verify Agent Worker is Running

### Check Railway Logs
```bash
railway logs | grep -i agent
```

Look for:
- `🚀 Starting agent worker...`
- `✅ Agent worker process started (PID: ...)`
- `🔌 Connecting to LiveKit Cloud...`
- `Agent name: agent`

### Check Agent Logs Directly
```bash
# On Railway, check the agent log file
tail -f /tmp/agent.log
```

Look for:
- `✅ All required environment variables are set`
- `🚀 Starting LiveKit Agent Worker`
- `📋 Agent name for dispatch: agent`
- `🔌 Connecting to LiveKit Cloud...`
- `The agent will listen for dispatches and join rooms as needed.`

### Check Health Endpoint
```bash
curl https://shaw.up.railway.app/health/agent
```

Response shows:
- `agent_status: "livekit_connected"` - LiveKit API works
- `agent_worker_info.agent_name` - Expected agent name
- Instructions to check logs

### Verify Agent Joined Room
When you start a session, check server logs for:
```
🚀 Starting agent dispatch process for room room-abc123
📡 Dispatching agent to room room-abc123 (attempt 1/3)...
✅ Agent dispatched to room room-abc123: dispatch-123
🔍 Verifying agent joined room room-abc123...
✅ Agent verified in room room-abc123: agent-xyz (SID: PA_abc)
```

If you see:
```
❌ CRITICAL: Agent dispatch succeeded but agent did not join room room-abc123
```

This means:
- Dispatch API call succeeded ✅
- But agent worker didn't receive/process the dispatch ❌
- Check agent worker logs immediately

## Testing the Fix

1. **Deploy updated code** to Railway
2. **Check agent worker starts** - Look for logs showing worker registration
3. **Start a session** from iOS app
4. **Watch server logs** for dispatch and verification
5. **Check agent logs** to see if entrypoint is called
6. **Verify transcript appears** when you speak

## Expected Flow

```
1. Client requests session start
   → Backend creates room name
   → Backend dispatches agent to room
   
2. Agent dispatch
   → LiveKit API accepts dispatch request ✅
   → LiveKit Cloud routes dispatch to registered worker
   → Worker receives dispatch and calls entrypoint()
   
3. Agent joins
   → entrypoint() called with JobContext
   → AgentSession.start() connects to room
   → Room auto-created if needed ✅
   → Agent joins as participant
   
4. Verification
   → Backend checks room participants
   → Finds agent participant ✅
   → Logs success
   
5. Conversation
   → Client speaks
   → Agent processes audio
   → Transcript saved to database ✅
```

## Key Changes Made

1. ✅ **Switched to LiveKit Inference** - Using `llm="openai/gpt-5-mini"` instead of OpenAI Realtime
2. ✅ **Better agent name handling** - Configurable via env var, logged on startup
3. ✅ **Room auto-creation awareness** - Verification understands rooms are auto-created
4. ✅ **Enhanced logging** - More diagnostic information throughout
5. ✅ **Health check improvements** - Shows agent worker info and expected agent name

## Next Steps

1. **Deploy and test** - Verify agent worker starts and registers
2. **Monitor logs** - Watch for agent entrypoint being called
3. **Check Railway** - Ensure Python process is running and stable
4. **Verify dispatch** - Confirm agent receives dispatches and joins rooms

If agent still doesn't join after these fixes, the issue is likely:
- Agent worker process not running (check Railway logs)
- Agent worker not connecting to LiveKit Cloud (check agent logs)
- Network/firewall issues preventing worker connection

