#!/bin/bash
# ===========================================
# DATAPLEX BUSINESS UI - QUICK DEPLOY
# ===========================================
# One script: setup + deploy

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Dataplex Business UI - Quick Deploy${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check config exists
if [ ! -f "$SCRIPT_DIR/config.env" ]; then
    echo -e "${RED}ERROR: config.env not found!${NC}"
    echo ""
    echo "Edit config.env first:"
    echo "  nano $SCRIPT_DIR/config.env"
    exit 1
fi

# Step 1: Setup roles
echo -e "${BLUE}STEP 1: Setting up IAM roles...${NC}"
echo ""
cd "$SCRIPT_DIR"
chmod +x setup-roles.sh
./setup-roles.sh

# Step 2: Deploy
echo ""
echo -e "${BLUE}STEP 2: Deploying to Cloud Run...${NC}"
echo ""
cd "$PROJECT_DIR"
chmod +x deploy.sh
./deploy.sh --config deployment/deploy.env

# Done
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  DEPLOYMENT COMPLETE!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT - Update OAuth redirect URI:${NC}"
echo "  1. Go to: https://console.cloud.google.com/apis/credentials"
echo "  2. Edit your OAuth 2.0 Client ID"
echo "  3. Add: https://YOUR_CLOUD_RUN_URL/auth/google/callback"
echo ""
