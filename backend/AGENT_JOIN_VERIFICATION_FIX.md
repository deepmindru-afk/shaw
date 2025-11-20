# Agent Join Verification Fix

## Problem

The agent was being dispatched to rooms, but there was no verification that it actually joined. This led to situations where:
- The client would connect and start speaking
- The agent never joined the room
- No transcript appeared because the agent wasn't there to process audio

This happened repeatedly because there was no verification or retry mechanism.

## Solution

Implemented a comprehensive agent dispatch and verification system that:

1. **Retries agent dispatch** with exponential backoff (up to 3 attempts)
2. **Verifies agent joined** by checking room participants (up to 15 attempts over 7.5 seconds)
3. **Logs comprehensive diagnostics** to help identify issues
4. **Provides health check endpoint** to verify agent worker status

## Changes Made

### 1. Enhanced `livekit.js`

**New Functions:**
- `verifyAgentJoined()` - Checks room participants to verify agent joined
- `dispatchAgentWithRetry()` - Dispatches agent with retry logic
- Enhanced `dispatchAgentToRoom()` - Now includes verification step

**Key Features:**
- Retry logic with exponential backoff (1s, 2s, 4s delays)
- Participant verification that checks multiple identity patterns
- Comprehensive logging of all participants for debugging
- Flexible agent identity detection (handles various LiveKit identity formats)

### 2. Enhanced `server.js`

**Improvements:**
- Better error handling and logging for agent dispatch
- Critical error messages when agent dispatch fails
- Instructions for debugging (check agent logs, verify worker is running)

### 3. Enhanced `agent.py`

**Improvements:**
- Logs agent identity when joining rooms
- Better visibility into which identity the agent uses

### 4. Enhanced Health Check Endpoint

**New `/health/agent` endpoint:**
- Verifies LiveKit API connectivity
- Shows last room activity
- Provides debugging instructions

## How It Works

1. **Client requests session start** → Backend creates room and dispatches agent
2. **Agent dispatch with retry** → Up to 3 attempts with exponential backoff
3. **Verification loop** → Checks room participants every 500ms for up to 7.5 seconds
4. **Success/failure logging** → Comprehensive logs help identify issues

## Verification Process

The verification checks for participants with identities matching:
- Starting with "agent"
- Containing "agent"
- Starting with "assistant"
- Containing "assistant"
- Exact match "agent"
- Any identity that doesn't start with "user-" or "device-" (to exclude clients)

## Logging

### Successful Dispatch
```
🚀 Starting agent dispatch process for room room-abc123 (session: session-xyz)
📡 Dispatching agent to room room-abc123 (attempt 1/3)...
✅ Agent dispatched to room room-abc123: dispatch-123
🔍 Verifying agent joined room room-abc123...
👥 Room room-abc123 has 1 participant(s):
   - agent-abc123 (SID: PA_xyz)
✅ Agent verified in room room-abc123: agent-abc123 (SID: PA_xyz)
✅ Agent successfully joined room room-abc123 - ready for conversation
```

### Failed Dispatch
```
❌ Failed to dispatch agent (attempt 1/3): Connection refused
⏳ Retrying in 1000ms...
❌ Failed to dispatch agent (attempt 2/3): Connection refused
⏳ Retrying in 2000ms...
❌ Failed to dispatch agent after 3 attempts: Connection refused
❌ CRITICAL: Failed to dispatch agent for session session-xyz: Failed to dispatch agent after 3 attempts: Connection refused
   Room: room-abc123
   This session may not work - agent will not join the room
   Check if agent worker is running: ps aux | grep "agent.py"
   Check agent logs: tail -f /tmp/agent.log
```

### Agent Not Joining (Dispatch Succeeds but Verification Fails)
```
✅ Agent dispatched to room room-abc123: dispatch-123
🔍 Verifying agent joined room room-abc123...
⏳ [1/15] No participants found in room room-abc123 yet
⏳ [2/15] No participants found in room room-abc123 yet
...
⏳ [15/15] No participants found in room room-abc123 yet
❌ CRITICAL: Agent dispatch succeeded but agent did not join room room-abc123
   Dispatch ID: dispatch-123
   This may indicate the agent worker is not running or not responding to dispatches
   Check agent logs: tail -f /tmp/agent.log
```

## Debugging

### Check Agent Worker Status
```bash
# Check if agent process is running
ps aux | grep "agent.py"

# Check agent logs
tail -f /tmp/agent.log

# Check Railway logs
railway logs | grep -i agent
```

### Check Health Endpoint
```bash
curl https://roadtrip.up.railway.app/health/agent
```

Response:
```json
{
  "agent_configured": true,
  "agent_status": "livekit_connected",
  "livekit_url": "wss://...",
  "last_room_activity": {
    "room_name": "room-abc123",
    "num_participants": 2,
    "created_at": "2025-01-11T12:00:00Z"
  },
  "timestamp": "2025-01-11T12:00:00Z",
  "note": "LiveKit API is accessible. Agent worker status cannot be verified via API - check logs for agent process."
}
```

### Check Server Logs
Look for these patterns:
- `🚀 Starting agent dispatch process` - Dispatch started
- `✅ Agent dispatched` - Dispatch succeeded
- `✅ Agent verified` - Agent joined room
- `❌ CRITICAL` - Critical errors that need attention

## Testing

1. **Start a session** from the iOS app
2. **Watch server logs** for dispatch and verification messages
3. **Check agent logs** to see agent joining
4. **Verify transcript appears** when you speak

## Permanent Fix Benefits

1. **Automatic retry** - Handles transient network issues
2. **Verification** - Ensures agent actually joins before client speaks
3. **Better diagnostics** - Comprehensive logging helps identify root causes
4. **Health checks** - Easy way to verify system status
5. **Non-blocking** - Client still gets token even if verification takes time

## Future Improvements

- Add metrics/monitoring for agent join success rate
- Add alerting when agent join verification fails repeatedly
- Consider making verification blocking (wait for agent before returning token)
- Add agent worker process health check (check if Python process is running)

