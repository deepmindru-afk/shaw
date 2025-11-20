# libstdc++.so.6 Fix for Railway Deployment

## Problem
The LiveKit Python agent worker fails to start on Railway with:
```
OSError: libstdc++.so.6: cannot open shared object file: No such file or directory
```

## Root Cause
Nixpacks installs the C++ standard library (`libstdc++.so.6`) but it's not in the runtime library search path (`LD_LIBRARY_PATH`). The LiveKit Python SDK's native C++ bindings can't find the required library at runtime.

## Solution Implemented

### Changes Made

1. **Updated `start.sh`** - Dynamic library path detection and export
   - Searches for `libstdc++.so.6` in common Nix locations
   - Dynamically sets `LD_LIBRARY_PATH` at runtime
   - Verifies Python can import LiveKit before starting
   - Captures agent worker logs for debugging
   - Validates agent worker startup before continuing

2. **Updated `nixpacks.toml`** - Added GCC package and build-time verification
   - Added `gcc` to nixPkgs (provides libstdc++)
   - Added build-time checks to verify library installation
   - Removed static `LD_LIBRARY_PATH` from variables (now set dynamically)

### How It Works

1. **Build Phase** (`nixpacks.toml`):
   - Installs `stdenv.cc.cc.lib` and `gcc` packages
   - Verifies library installation during build

2. **Runtime Phase** (`start.sh`):
   - Searches for `libstdc++.so.6` in:
     - `/root/.nix-profile/lib` (most common in Nixpacks)
     - `/nix/store/*/lib` (recursive search)
     - `/usr/lib` and `/usr/lib/x86_64-linux-gnu` (fallback)
   - Exports `LD_LIBRARY_PATH` with found library path
   - Verifies LiveKit can be imported
   - Starts agent worker with error logging
   - Validates agent worker is running before starting web server

## Testing

After deploying, check logs:

```bash
cd backend
railway up --detach
sleep 30
railway logs --lines 100
```

### Success Indicators
- ✅ "Found libstdc++.so.6 at: ..."
- ✅ "LD_LIBRARY_PATH set to: ..."
- ✅ "LiveKit Python SDK imported successfully"
- ✅ "Agent worker is running (PID: ...)"
- ✅ "Server running on http://localhost:3000"

### Failure Indicators
- ❌ "Warning: libstdc++.so.6 not found"
- ❌ "Failed to import LiveKit: OSError: libstdc++.so.6..."
- ❌ "Agent worker failed to start"

## Alternative Solutions (If This Doesn't Work)

### Option A: Use patchelf to Set RPATH

If dynamic `LD_LIBRARY_PATH` doesn't work, modify the LiveKit library directly:

**Update `nixpacks.toml`:**

```toml
[phases.setup]
nixPkgs = ['nodejs_20', 'python311', 'python311Packages.pip', 'python311Packages.virtualenv', 'stdenv.cc.cc.lib', 'gcc', 'patchelf']

[phases.install]
cmds = [
  'npm ci',
  'python3 -m venv /opt/venv',
  '/opt/venv/bin/pip install --upgrade pip',
  '/opt/venv/bin/pip install -r requirements.txt',
  'find /opt/venv/lib/python3.11/site-packages/livekit -name "*.so" -exec patchelf --set-rpath /root/.nix-profile/lib {} \; || true'
]
```

### Option B: Switch to Dockerfile

If Nixpacks continues to have issues, use a Dockerfile:

**Create `backend/Dockerfile`:**

```dockerfile
FROM node:20-slim

# Install Python and system dependencies
RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-venv libstdc++6 findutils && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Node.js dependencies
COPY package*.json ./
RUN npm ci

# Install Python dependencies
COPY requirements.txt ./
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip && \
    /opt/venv/bin/pip install -r requirements.txt

# Copy application files
COPY . .

# Set environment
ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH

CMD ["bash", "start.sh"]
```

**Update `railway.json`:**

```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "DOCKERFILE",
    "dockerfilePath": "Dockerfile"
  },
  "deploy": {
    "startCommand": "bash start.sh",
    "restartPolicyType": "ON_FAILURE",
    "restartPolicyMaxRetries": 10
  }
}
```

### Option C: Use Nix Flakes (Advanced)

Create a `backend/flake.nix` for more control:

```nix
{
  description = "Roadtrip Backend";
  
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
  
  outputs = { self, nixpkgs }: {
    defaultPackage.x86_64-linux = 
      let pkgs = import nixpkgs { system = "x86_64-linux"; };
      in pkgs.buildEnv {
        name = "roadtrip-backend";
        paths = [
          pkgs.nodejs_20
          pkgs.python311
          pkgs.gcc
          pkgs.stdenv.cc.cc.lib
        ];
      };
  };
}
```

## Debugging Commands

If the fix doesn't work, run these in Railway shell:

```bash
# Find the library
find /nix/store -name "libstdc++.so.6" 2>/dev/null

# Check what libraries LiveKit needs
ldd /opt/venv/lib/python3.11/site-packages/livekit/rtc/*.so

# Check current LD_LIBRARY_PATH
echo $LD_LIBRARY_PATH

# Test Python import
/opt/venv/bin/python -c "import livekit; print('OK')"
```

## Files Modified

- `backend/start.sh` - Dynamic library path detection and runtime setup
- `backend/nixpacks.toml` - Added GCC package and build verification

## Next Steps

1. **Deploy and test** the current solution
2. **Check logs** for success/failure indicators
3. **If it fails**, try Option A (patchelf) or Option B (Dockerfile)
4. **Report results** - The logs will show exactly where the library was found (or not found)

