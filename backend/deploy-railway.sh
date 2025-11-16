#!/bin/bash
# Quick Railway Deployment Script
# Run this after initial setup is complete

set -e

echo "🚀 Deploying to Railway..."
railway up

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Getting URL..."
railway status

