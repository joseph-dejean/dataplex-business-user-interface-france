#!/bin/bash
# =============================================================================
# Push Script - Triggers Continuous Deployment automatically
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo -e "${RED}[✗] Error: Please provide a commit message.${NC}"
    echo "Usage: ./push.sh \"your commit message\""
    exit 1
fi

COMMIT_MESSAGE=$1

echo -e "\n${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}  Starting Automated Push & Deployment     ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}\n"

echo -e "${GREEN}[1/3]${NC} Staging all changes..."
git add .

echo -e "${GREEN}[2/3]${NC} Committing with message: \"$COMMIT_MESSAGE\""
git commit -m "$COMMIT_MESSAGE" || { echo -e "${RED}[!] No changes to commit.${NC}"; exit 0; }

echo -e "${GREEN}[3/3]${NC} Pushing to origin main..."
git push origin main

echo -e "\n${GREEN}[✓] Success!${NC}"
echo "Your code has been pushed to GitHub."
echo "Google Cloud Build is now building and deploying your changes in the background."
echo "You can view the progress in the Google Cloud Console under 'Cloud Build'."
