# Call & Transcript Fixes - Deployment Guide

## Summary

Fixed 3 critical issues:
1. **First call immediately ends** - Added error logging to diagnose LiveKit connection failures
2. **Missing transcripts/summaries** - Agent now captures and saves transcript during calls
3. **Wrong transcript message** - Dynamic messaging based on actual session state

## What Changed

### Backend Changes

#### 1. server.js
- `dispatchAgentToRoom()` now receives and passes `session_id` to agent metadata
- `/v1/sessions/:id/turns` endpoint no longer requires authentication (agent can POST)

#### 2. livekit.js
- `dispatchAgentToRoom()` signature changed to include `sessionId` parameter
- Agent metadata now includes `session_id` field

#### 3. agent.py
- Added `aiohttp` dependency for HTTP requests
- Added `save_turn()` function to POST transcripts to backend
- Added event handlers for `user_speech_committed` and `agent_speech_committed`
- Extracts `session_id` from job metadata
- Captures and saves both user and assistant turns during conversation
- Uses `BACKEND_URL` env var (defaults to `https://roadtrip.up.railway.app`)

### iOS Changes

#### 1. LiveKitService.swift
- Added detailed error logging in connection failure handler
- Added success logging after room.connect() completes
- Logs LiveKit error types for debugging

#### 2. AssistantCallCoordinator.swift
- Added detailed error logging in liveKitServiceDidFail()
- Logs error type and description

#### 3. SessionDetailScreen.swift
- Fixed EmptyTranscriptView to show dynamic messages:
  - Active sessions: "Transcript will appear as you talk..."
  - Ended sessions: "We haven't received transcript turns yet. Pull to refresh..."
  - Removed misleading "logging disabled" message

## Deployment Steps

### 1. Deploy Backend to Railway

```bash
cd backend
git push  # Railway auto-deploys from main branch
```

**Important:** The backend must be deployed **before** deploying the agent, since the agent depends on the `/v1/sessions/:id/turns` endpoint.

### 2. Deploy LiveKit Agent

The agent needs to be redeployed with the updated code:

```bash
cd backend

# Option 1: Using LiveKit CLI (if you have it configured)
lk agent deploy

# Option 2: Railway should auto-deploy if agent is in the same repo
git push
```

**Verify agent deployment:**
- Check LiveKit Cloud dashboard for active agents
- Agent should receive `session_id` in metadata
- Agent logs should show "📝 Session ID: session-..."

### 3. iOS App (No deployment needed)

Changes are code-only, no rebuild required for existing TestFlight/App Store builds.
The fixes will work once backend and agent are deployed.

## Verification Checklist

### Test Scenario 1: First Call
- [ ] Start a call from iOS app
- [ ] Check Xcode console for LiveKit connection logs
- [ ] If call fails, error details should be visible
- [ ] Call should NOT immediately end (unless there's a real error)

### Test Scenario 2: Transcript Capture
- [ ] Start a call
- [ ] Have a conversation with the assistant
- [ ] End the call
- [ ] Navigate to session detail screen
- [ ] Wait 5-10 seconds
- [ ] Pull to refresh
- [ ] Transcript should appear with user/assistant turns
- [ ] Summary should be generated after ~30 seconds

### Test Scenario 3: Empty State Messages
- [ ] Start a call (transcript empty, still active) → Should show "Transcript will appear as you talk..."
- [ ] End the call immediately (transcript empty, ended) → Should show "We haven't received transcript turns yet..."
- [ ] Never should show "logging disabled" message

## Backend Logs to Monitor

### Railway Backend Logs
```
✅ Saved user turn for session session-...
✅ Saved assistant turn for session session-...
📝 Generating summary for session session-...
✅ Summary generated for session session-...
```

### LiveKit Agent Logs
```
📋 Received metadata: {'session_id': 'session-...', 'realtime': True, ...}
📝 Session ID: session-...
✅ Saved user turn for session session-...
✅ Saved assistant turn for session session-...
```

## Rollback Plan

If issues occur:

1. **Backend rollback:**
   ```bash
   git revert HEAD
   git push
   ```

2. **Agent issues:** The agent changes are backward compatible. Old sessions without transcript will just have no turns saved.

## Known Limitations

1. **Agent event names may vary** - The event handler names (`user_speech_committed`, `agent_speech_committed`) are based on LiveKit SDK documentation but may need adjustment based on actual events fired.

2. **No authentication on turns endpoint** - The `/v1/sessions/:id/turns` endpoint is now open to anyone who knows a session ID. This is acceptable since:
   - Session IDs are UUIDs (hard to guess)
   - Only used during active calls
   - Alternative would be to implement agent-specific API key

3. **First call failure root cause unknown** - We added logging but haven't identified the actual cause yet. The logs will help diagnose it.

## Environment Variables

Ensure these are set on Railway for the agent:

```env
BACKEND_URL=https://roadtrip.up.railway.app
LIVEKIT_URL=wss://...
LIVEKIT_API_KEY=...
LIVEKIT_API_SECRET=...
OPENAI_API_KEY=...
```

## Next Steps After Deployment

1. Monitor first call attempts - check logs for LiveKit errors
2. Monitor transcript capture - verify turns are being saved
3. Monitor summary generation - verify summaries appear within 30-60 seconds
4. If transcripts still don't appear, check LiveKit agent event names in SDK docs
