#!/bin/bash
# Railway Setup Script for AI Voice Copilot Backend

set -e

echo "🚀 Railway Deployment Setup"
echo "============================"
echo ""

# Check if Railway CLI is installed
if ! command -v railway &> /dev/null; then
    echo "❌ Railway CLI not found. Installing..."
    npm install -g @railway/cli
fi

echo "✅ Railway CLI is installed"
echo ""

# Step 1: Login
echo "📝 Step 1: Login to Railway"
echo "   This will open your browser for authentication..."
railway login

if [ $? -ne 0 ]; then
    echo "❌ Login failed. Please try again."
    exit 1
fi

echo ""
echo "✅ Logged in successfully!"
echo ""

# Step 2: Initialize project
echo "📝 Step 2: Initialize Railway project"
echo "   Creating new project: ai-voice-copilot-backend"
railway init --name ai-voice-copilot-backend

if [ $? -ne 0 ]; then
    echo "❌ Project initialization failed."
    exit 1
fi

echo ""
echo "✅ Project initialized!"
echo ""

# Step 3: Deploy first to create service
echo "📝 Step 3: Deploying to create service..."
railway up --detach

# Get service ID from status
SERVICE_ID=$(railway status 2>/dev/null | grep -i "service" | awk '{print $NF}' || echo "")

if [ -z "$SERVICE_ID" ]; then
    echo "   ⚠️  Could not get service ID automatically"
    echo "   Please set variables manually in Railway dashboard"
    echo "   https://railway.app/project/547fff28-a168-4fdb-9b84-cb9710ff0f15"
else
    echo "   ✅ Service created: $SERVICE_ID"
fi

echo ""
echo "📝 Step 4: Setting environment variables..."

# Read from .env file if it exists
if [ -f .env ]; then
    echo "   Reading LiveKit credentials from .env file..."
    source .env
    
    if [ -n "$SERVICE_ID" ]; then
        railway variables --service "$SERVICE_ID" \
                          --set "LIVEKIT_API_KEY=$LIVEKIT_API_KEY" \
                          --set "LIVEKIT_API_SECRET=$LIVEKIT_API_SECRET" \
                          --set "LIVEKIT_URL=$LIVEKIT_URL" \
                          --set "NODE_ENV=production" \
                          --set "PORT=3000" \
                          --set "DATABASE_PATH=/tmp/sessions.db"
    else
        echo "   ⚠️  Setting variables without service ID..."
        railway variables --set "LIVEKIT_API_KEY=$LIVEKIT_API_KEY" \
                          --set "LIVEKIT_API_SECRET=$LIVEKIT_API_SECRET" \
                          --set "LIVEKIT_URL=$LIVEKIT_URL" \
                          --set "NODE_ENV=production" \
                          --set "PORT=3000" \
                          --set "DATABASE_PATH=/tmp/sessions.db"
    fi
else
    echo "   ⚠️  .env file not found. Please set variables manually:"
    echo "   railway variables --set \"LIVEKIT_API_KEY=your_key\""
    echo "   railway variables --set \"LIVEKIT_API_SECRET=your_secret\""
    echo "   railway variables --set \"LIVEKIT_URL=your_url\""
fi

echo ""
echo "✅ Environment variables set!"
echo ""

# Step 4: Deploy
echo "📝 Step 4: Deploying to Railway..."
echo "   This may take a few minutes..."
railway up

if [ $? -ne 0 ]; then
    echo "❌ Deployment failed. Check the logs above."
    exit 1
fi

echo ""
echo "✅ Deployment complete!"
echo ""

# Step 5: Get URL
echo "📝 Step 5: Getting deployment URL..."
RAILWAY_URL=$(railway domain 2>/dev/null || railway status | grep -oP 'https://[^\s]+' | head -1)

if [ -z "$RAILWAY_URL" ]; then
    echo "   ⚠️  Could not automatically get URL. Check Railway dashboard:"
    echo "   https://railway.app"
    echo ""
    echo "   Your API will be at: https://your-project.up.railway.app/v1"
else
    echo "   ✅ Your backend is live at:"
    echo "   $RAILWAY_URL"
    echo ""
    echo "   API endpoint: $RAILWAY_URL/v1"
    echo ""
    echo "   Update your iOS app's API_BASE_URL to:"
    echo "   $RAILWAY_URL/v1"
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "1. Test your API: curl $RAILWAY_URL/health"
echo "2. Update iOS app Configuration.swift with the URL above"
echo "3. Check Railway dashboard for logs and monitoring"

