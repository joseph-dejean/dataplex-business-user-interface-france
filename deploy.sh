#!/bin/bash
# =============================================================================
# Dataplex Business User Interface - Cloud Run Deployment Script
# =============================================================================
# This script automates the full deployment to Google Cloud Run.
#
# Prerequisites:
#   - gcloud CLI installed and authenticated (gcloud auth login)
#   - A GCP project with the following APIs enabled:
#       * Cloud Run, Artifact Registry, Cloud Build
#       * Dataplex, BigQuery, Data Catalog, Data Lineage
#       * Firestore, IAM
#   - An OAuth 2.0 Client ID (Web Application type)
#
# Usage:
#   ./deploy.sh                     # Interactive — prompts for all values
#   ./deploy.sh --config deploy.env # Use a config file
#   ./deploy.sh --local-build       # Build locally with Docker (default: Cloud Build)
#
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No color

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }
info()  { echo -e "${BLUE}[i]${NC} $1"; }
header(){ echo -e "\n${BLUE}═══════════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}═══════════════════════════════════════════${NC}\n"; }

# ---------- Parse flags ----------
USE_CLOUD_BUILD=true  # Default to Cloud Build (more reliable in Cloud Shell)
CONFIG_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --local-build) USE_CLOUD_BUILD=false; shift ;;
    --cloud-build) USE_CLOUD_BUILD=true; shift ;;  # kept for backwards compatibility
    --config)      CONFIG_FILE="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: ./deploy.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --config FILE    Load configuration from file (see deploy.env.example)"
      echo "  --local-build    Build image locally with Docker (default: Cloud Build)"
      echo "  -h, --help       Show this help message"
      exit 0
      ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
done

# ---------- Load config or prompt ----------
header "Dataplex Business UI — Cloud Run Deployment"

if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    err "Config file not found: $CONFIG_FILE"
    exit 1
  fi
  info "Loading config from $CONFIG_FILE"
  source "$CONFIG_FILE"
else
  info "No config file provided. Running in interactive mode."
  info "Tip: run with --config deploy.env to skip prompts next time.\n"
fi

prompt_var() {
  local var_name=$1
  local description=$2
  local default=$3
  local is_secret=${4:-false}

  # If already set (from config file or env), keep it
  if [[ -n "${!var_name}" ]]; then
    if [[ "$is_secret" == "true" ]]; then
      log "$description: ****"
    else
      log "$description: ${!var_name}"
    fi
    return
  fi

  if [[ -n "$default" ]]; then
    read -p "  $description [$default]: " value
    value="${value:-$default}"
  else
    if [[ "$is_secret" == "true" ]]; then
      read -sp "  $description: " value
      echo ""
    else
      read -p "  $description: " value
    fi
  fi

  if [[ -z "$value" ]]; then
    err "$description is required."
    exit 1
  fi

  eval "$var_name='$value'"
}

# ---------- Gather configuration ----------
header "1. GCP Project Configuration"

# Try to detect current project
DETECTED_PROJECT=$(gcloud config get-value project 2>/dev/null || true)

prompt_var "GCP_PROJECT_ID"     "GCP Project ID"           "$DETECTED_PROJECT"
prompt_var "GCP_REGION"         "GCP Region"               "europe-west1"
prompt_var "SERVICE_NAME"       "Cloud Run Service Name"    "dataplex-business-ui"
prompt_var "ARTIFACT_REPO_NAME" "Artifact Registry Repo"    "dataplex-business-ui"
prompt_var "IMAGE_NAME"         "Docker Image Name"         "dataplex-business-ui"

header "2. OAuth 2.0 Credentials"
info "Create at: https://console.cloud.google.com/auth/clients"

prompt_var "OAUTH_CLIENT_ID"     "OAuth Client ID"         "" false
prompt_var "OAUTH_CLIENT_SECRET" "OAuth Client Secret"     "" true

header "3. Application Settings"

prompt_var "ADMIN_EMAIL"  "Super Admin Email"    ""
prompt_var "GCP_LOCATION" "Dataplex Location"    "$GCP_REGION"
prompt_var "EXTERNAL_PROJECTS" "External Projects (space-separated, optional)" ""

# Derive values
IMAGE_TAG=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")
IMAGE_URI="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${ARTIFACT_REPO_NAME}/${IMAGE_NAME}"

# ---------- Pre-flight checks ----------
header "4. Pre-flight Checks"

# Check gcloud
if ! command -v gcloud &>/dev/null; then
  err "gcloud CLI not found. Install it from https://cloud.google.com/sdk/docs/install"
  exit 1
fi
log "gcloud CLI found"

# Check project access
if gcloud projects describe "$GCP_PROJECT_ID" &>/dev/null; then
  log "Project $GCP_PROJECT_ID accessible"
else
  err "Cannot access project $GCP_PROJECT_ID. Check your gcloud auth."
  exit 1
fi

# Enable required APIs
info "Enabling required APIs (this may take a minute)..."
REQUIRED_APIS=(
  "run.googleapis.com"
  "artifactregistry.googleapis.com"
  "cloudbuild.googleapis.com"
  "dataplex.googleapis.com"
  "bigquery.googleapis.com"
  "datacatalog.googleapis.com"
  "datalineage.googleapis.com"
  "firestore.googleapis.com"
  "iam.googleapis.com"
  "aiplatform.googleapis.com"
  "cloudresourcemanager.googleapis.com"
  "geminidataanalytics.googleapis.com"
  "cloudaicompanion.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
  gcloud services enable "$api" --project="$GCP_PROJECT_ID" --quiet 2>/dev/null && \
    log "API enabled: $api" || warn "Could not enable $api (may already be enabled)"
done

# Create Artifact Registry repo if it doesn't exist
if ! gcloud artifacts repositories describe "$ARTIFACT_REPO_NAME" \
    --location="$GCP_REGION" --project="$GCP_PROJECT_ID" &>/dev/null; then
  info "Creating Artifact Registry repository..."
  gcloud artifacts repositories create "$ARTIFACT_REPO_NAME" \
    --repository-format=docker \
    --location="$GCP_REGION" \
    --project="$GCP_PROJECT_ID" \
    --description="Dataplex Business UI Docker images"
  log "Artifact Registry repo created"
else
  log "Artifact Registry repo exists"
fi

# Check Firestore
if ! gcloud firestore databases describe --project="$GCP_PROJECT_ID" &>/dev/null; then
  warn "Firestore not initialized. Creating default database..."
  gcloud firestore databases create \
    --project="$GCP_PROJECT_ID" \
    --location="$GCP_REGION" \
    --type=firestore-native 2>/dev/null || \
  warn "Could not create Firestore DB — you may need to do this manually in the console."
else
  log "Firestore database exists"
fi

# ---------- Build ----------
header "5. Building Docker Image"

if [[ "$USE_CLOUD_BUILD" == "true" ]]; then
  info "Building remotely with Cloud Build..."
  gcloud builds submit . \
    --tag="${IMAGE_URI}:${IMAGE_TAG}" \
    --project="$GCP_PROJECT_ID" \
    --region="$GCP_REGION" \
    --quiet

  # Also tag as latest
  gcloud artifacts docker tags add \
    "${IMAGE_URI}:${IMAGE_TAG}" \
    "${IMAGE_URI}:latest" \
    --quiet 2>/dev/null || true
else
  if ! command -v docker &>/dev/null; then
    err "Docker not found. Install Docker or use --cloud-build flag."
    exit 1
  fi

  info "Configuring Docker for Artifact Registry..."
  gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet

  info "Building image locally..."
  docker build -t "${IMAGE_URI}:${IMAGE_TAG}" -t "${IMAGE_URI}:latest" .

  info "Pushing image..."
  docker push "${IMAGE_URI}:${IMAGE_TAG}"
  docker push "${IMAGE_URI}:latest"
fi

log "Image built and pushed: ${IMAGE_URI}:${IMAGE_TAG}"

# ---------- Deploy ----------
header "6. Deploying to Cloud Run"

# Build the env vars string
# NOTE: VITE_* vars are embedded in frontend JS at build time
# Do NOT put secrets in VITE_* vars - they are exposed to browsers!
ENV_VARS="VITE_API_URL=/api"
ENV_VARS+=",VITE_API_VERSION=v1"
ENV_VARS+=",VITE_GOOGLE_PROJECT_ID=${GCP_PROJECT_ID}"
ENV_VARS+=",VITE_GOOGLE_CLIENT_ID=${OAUTH_CLIENT_ID}"
ENV_VARS+=",VITE_GOOGLE_REDIRECT_URI=/auth/google/callback"
ENV_VARS+=",VITE_ADMIN_EMAIL=${ADMIN_EMAIL}"
ENV_VARS+=",GOOGLE_CLOUD_PROJECT_ID=${GCP_PROJECT_ID}"
ENV_VARS+=",GOOGLE_CLOUD_PROJECT=${GCP_PROJECT_ID}"
ENV_VARS+=",GCP_PROJECT=${GCP_PROJECT_ID}"
ENV_VARS+=",GCP_LOCATION=${GCP_LOCATION}"
ENV_VARS+=",GCP_REGION=${GCP_REGION}"
ENV_VARS+=",SUPER_ADMIN_EMAIL=${ADMIN_EMAIL}"
ENV_VARS+=",GOOGLE_CLIENT_SECRET=${OAUTH_CLIENT_SECRET}"

# Add external projects if configured
if [[ -n "$EXTERNAL_PROJECTS" ]]; then
  ENV_VARS+=",EXTERNAL_PROJECTS=${EXTERNAL_PROJECTS}"
  info "External projects: ${EXTERNAL_PROJECTS}"
fi

info "Deploying service..."
gcloud run deploy "$SERVICE_NAME" \
  --image="${IMAGE_URI}:${IMAGE_TAG}" \
  --platform=managed \
  --region="$GCP_REGION" \
  --port=8080 \
  --allow-unauthenticated \
  --set-env-vars="$ENV_VARS" \
  --memory=512Mi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=10 \
  --project="$GCP_PROJECT_ID" \
  --quiet

# Get the service URL
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
  --platform=managed \
  --region="$GCP_REGION" \
  --project="$GCP_PROJECT_ID" \
  --format="value(status.url)")

log "Deployed successfully!"

# ---------- Post-deploy ----------
header "7. Post-Deployment"

echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Deployment Complete!                                  ║${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}  Service URL:  ${BLUE}${SERVICE_URL}${NC}"
echo -e "${GREEN}║${NC}  Project:      ${GCP_PROJECT_ID}"
echo -e "${GREEN}║${NC}  Region:       ${GCP_REGION}"
echo -e "${GREEN}║${NC}  Image:        ${IMAGE_URI}:${IMAGE_TAG}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"

echo ""
warn "Don't forget to:"
echo "  1. Add ${SERVICE_URL}/auth/google/callback to your OAuth redirect URIs"
echo "     → https://console.cloud.google.com/auth/clients"
echo "  2. Grant the Cloud Run service account these roles:"
echo "     → Dataplex Admin (or Dataplex Editor + Dataplex Data Reader)"
echo "     → BigQuery Data Viewer"
echo "     → Data Catalog Viewer"
echo "     → Firestore User"
echo "  3. Initialize Firestore collections (they auto-create on first use)"
echo ""
info "To save this configuration for next time, run:"
echo ""
echo "  cat > deploy.env << 'EOF'"
echo "  GCP_PROJECT_ID=${GCP_PROJECT_ID}"
echo "  GCP_REGION=${GCP_REGION}"
echo "  GCP_LOCATION=${GCP_LOCATION}"
echo "  SERVICE_NAME=${SERVICE_NAME}"
echo "  ARTIFACT_REPO_NAME=${ARTIFACT_REPO_NAME}"
echo "  IMAGE_NAME=${IMAGE_NAME}"
echo "  OAUTH_CLIENT_ID=${OAUTH_CLIENT_ID}"
echo "  OAUTH_CLIENT_SECRET=<your-secret>"
echo "  ADMIN_EMAIL=${ADMIN_EMAIL}"
echo "  EOF"
echo ""
