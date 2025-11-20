# Railway Configuration Files

## Current Setup

We deploy from the **repo root** with Root Directory = `.` in Railway dashboard.

### Main Service (Node.js + Python Agent)

**File**: `railway.json` (at repo root)
- **Purpose**: Combined service running both Node.js server and Python agent
- **Start Command**: `bash start.sh` (wrapper that calls `backend/start.sh`)
- **Build Config**: `nixpacks.toml` (at repo root)

### Python-Only Service (If Needed in Future)

**Files**: `backend/start-agent.sh` and `backend/nixpacks-agent.toml`
- **Purpose**: If you create a separate Railway service that runs ONLY the Python agent
- **Start Command**: `bash start-agent.sh`
- **Build Config**: `backend/nixpacks-agent.toml`
- **Note**: Configure these settings directly in Railway dashboard if creating a separate service

## File Structure

```
roadtrip-app/
├── railway.json              ← Main service config (Node.js + Python)
├── nixpacks.toml             ← Main service build config
├── start.sh                  ← Wrapper script (calls backend/start.sh)
└── backend/
    ├── start.sh              ← Actual startup script
    ├── start-agent.sh        ← Python-only startup script (if needed)
    └── nixpacks-agent.toml   ← Python-only build config (if needed)
```

## Railway Dashboard Settings

### Main Service
- **Root Directory**: `.` (root)
- **Nixpacks Config Path**: `nixpacks.toml` (or leave empty, Railway will find it)
- **Start Command**: `bash start.sh` (or leave empty, uses railway.json)

### Python Service (if separate)
- **Root Directory**: `backend`
- **Nixpacks Config Path**: `nixpacks-agent.toml`
- **Start Command**: `bash start-agent.sh`

## Why This Structure?

- **Single source of truth**: Main service uses root-level configs
- **Clear separation**: Python-only service has its own configs in backend/
- **Works with CLI**: `railway up` from root works correctly
- **Works with GitHub**: Auto-deploy works correctly

## Removed Files

- ~~`backend/railway.json`~~ - Removed, no longer needed (replaced by root `railway.json`)
- ~~`backend/railway-agent.json`~~ - Removed, not needed (configure Python service directly in dashboard if needed)

