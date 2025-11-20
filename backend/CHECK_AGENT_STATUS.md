# How to Check Agent Status on LiveKit Cloud

## Critical Issue Found

The agent worker process starts (PID: 9) but **no entrypoint logs appear**. This means:
- ✅ Agent worker process is running
- ❌ Agent worker is NOT receiving dispatches OR not connected to LiveKit Cloud

## Check LiveKit Cloud Logs

### Option 1: LiveKit Cloud Dashboard (Preferred)

1. Go to https://cloud.livekit.io/
2. Select your project: `bunnyai` or `bunnyai2`
3. Navigate to **Agents** section
4. Check:
   - Is there a deployed agent? (should be `roadtrip-voice-assistant` if deployed to cloud)
   - Are there any running agent instances?
   - Check agent logs in the dashboard

### Option 2: LiveKit CLI

```bash
cd backend

# List agents
lk agent list

# View agent logs (if agent is deployed to LiveKit Cloud)
lk agent logs roadtrip-voice-assistant

# Check dispatch status
lk dispatch list --room <room-name>
```

### Option 3: Railway Logs

The agent worker should output logs to stdout. Check for:
- `🚀 Starting LiveKit Agent Worker`
- `📋 Agent name for dispatch: agent`
- `🔌 Connecting to LiveKit Cloud...`
- `🎙️  Agent entrypoint called!` (when dispatch received)

## Key Questions to Answer

1. **Is the agent worker actually connected to LiveKit Cloud?**
   - Look for connection success messages
   - Check if worker is registered and listening

2. **Is the agent name correct?**
   - Backend dispatches to: `'agent'`
   - Agent worker uses: `agent_name="agent"` (or `LIVEKIT_AGENT_NAME` env var)
   - These MUST match

3. **Is the agent worker receiving dispatches?**
   - Look for `🎙️  Agent entrypoint called!` in logs
   - If missing, worker isn't receiving dispatches

4. **Are there errors preventing connection?**
   - Check for Python import errors
   - Check for LiveKit SDK connection errors
   - Check for missing environment variables

## Next Steps

1. **Check LiveKit Cloud Dashboard** - See if agent is deployed/running
2. **Check Railway logs** - See if agent worker connects
3. **Verify agent name matches** - Both must use `'agent'`
4. **Check dispatch ID** - `AD_3PkTWFrKkvSQ` was created, but did agent receive it?

## If Agent Worker is NOT Connected

The agent worker might be:
- Running but not connecting to LiveKit Cloud
- Connecting but not registering as available
- Registered but with wrong agent name
- Crashed after startup (check if PID 9 is still running)

## If Agent Worker IS Connected But Not Receiving Dispatches

Check:
- Agent name mismatch (dispatch uses `'agent'`, worker uses different name)
- LiveKit Cloud routing issue
- Network/firewall blocking connection

