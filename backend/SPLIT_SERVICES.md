# Splitting backend and agent into two Railway services

The repo can now run the Node backend and Python agent separately.

## Recommended service setup

1) **Backend service (Node API)**
   - Root directory: `backend`
   - Start command: `npm start`
   - Env vars: LiveKit API/Secret/URL, OPENAI_API_KEY, PERPLEXITY_API_KEY, DB vars, etc.
   - Set `DISABLE_EMBEDDED_AGENT=1` so it does not launch the agent worker.

2) **Agent service (Python worker)**
   - Root directory: `backend`
   - Start command: `bash start-agent.sh`
   - Env vars: LiveKit API/Secret/URL, `OPENAI_API_KEY`, `CARTESIA_API_KEY`, `ELEVENLABS_API_KEY`, other LLM keys as needed.
   - Optional: `LIVEKIT_AGENT_NAME` if you dispatch with a non-default name (defaults to `agent`).

## Why the flag?

`backend/start.sh` still supports the combined mode, but if you set `DISABLE_EMBEDDED_AGENT=1` it will skip starting the agent supervisor and only run `npm start`. This keeps the backend service slim while the dedicated agent service handles dispatches and room joins.

## Deploy order

1) Deploy the agent service first and watch logs for:  
   `Connecting to LiveKit Cloud…` and `Using TTS plugin directly (provider: cartesia|elevenlabs)`.
2) Deploy the backend service and start a session; the backend dispatches to the agent service using `LIVEKIT_AGENT_NAME` (default `agent`).
