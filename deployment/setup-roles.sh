#!/bin/bash
# ===========================================
# DATAPLEX BUSINESS UI - IAM SETUP SCRIPT
# ===========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Dataplex Business UI - IAM Setup${NC}"
echo -e "${BLUE}=========================================${NC}"

# Load configuration
if [ -f "config.env" ]; then
    source config.env
else
    echo -e "${RED}ERROR: config.env not found!${NC}"
    echo ""
    echo "Create it from the example:"
    echo "  cp config.env.example config.env"
    echo "  nano config.env"
    exit 1
fi

# Validate required variables
if [ -z "$GCP_PROJECT_ID" ] || [ "$GCP_PROJECT_ID" == "your-project-id" ]; then
    echo -e "${RED}ERROR: GCP_PROJECT_ID is not set in config.env${NC}"
    exit 1
fi

if [ -z "$OAUTH_CLIENT_ID" ] || [ "$OAUTH_CLIENT_ID" == "your-client-id.apps.googleusercontent.com" ]; then
    echo -e "${RED}ERROR: OAUTH_CLIENT_ID is not set!${NC}"
    echo "Create OAuth credentials at: https://console.cloud.google.com/apis/credentials"
    exit 1
fi

echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Project ID:         $GCP_PROJECT_ID"
echo "  Region:             $GCP_REGION"
echo "  External Projects:  ${EXTERNAL_PROJECTS:-None}"
echo "  Admin Email:        $ADMIN_EMAIL"
echo ""

# Set the project
echo -e "${BLUE}[1/4] Setting active project to $GCP_PROJECT_ID...${NC}"
gcloud config set project $GCP_PROJECT_ID

# Get project number
echo -e "${BLUE}[2/4] Getting project info...${NC}"
PROJECT_NUMBER=$(gcloud projects describe $GCP_PROJECT_ID --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo "  Project Number:    $PROJECT_NUMBER"
echo "  Service Account:   $SERVICE_ACCOUNT"

# Enable APIs
echo ""
echo -e "${BLUE}[3/4] Enabling required APIs...${NC}"
APIS=(
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

for api in "${APIS[@]}"; do
    echo "  Enabling $api..."
    gcloud services enable $api --quiet 2>/dev/null || true
done

# Grant roles to service account
echo ""
echo -e "${BLUE}[4/4] Granting runtime roles to service account...${NC}"

SA_ROLES=(
    "roles/dataplex.admin"
    "roles/bigquery.dataViewer"
    "roles/bigquery.metadataViewer"
    "roles/bigquery.jobUser"
    "roles/bigquery.dataOwner"
    "roles/datacatalog.viewer"
    "roles/datastore.user"
    "roles/datalineage.viewer"
    "roles/aiplatform.user"
    "roles/resourcemanager.projectIamAdmin"
    "roles/geminidataanalytics.dataAgentCreator"
    "roles/geminidataanalytics.dataAgentUser"
    "roles/cloudaicompanion.user"
    "roles/storage.objectAdmin"
)

for role in "${SA_ROLES[@]}"; do
    echo "  Granting $role..."
    gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
        --member="serviceAccount:$SERVICE_ACCOUNT" \
        --role="$role" \
        --quiet 2>/dev/null || true
done

# Grant Cloud Build service account roles (for --cloud-build deployments)
echo ""
echo -e "${BLUE}Granting Cloud Build service account roles...${NC}"
CLOUDBUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

CLOUDBUILD_ROLES=(
    "roles/storage.objectViewer"
    "roles/logging.logWriter"
    "roles/artifactregistry.writer"
)

for role in "${CLOUDBUILD_ROLES[@]}"; do
    echo "  Granting $role to Cloud Build SA..."
    gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
        --member="serviceAccount:$CLOUDBUILD_SA" \
        --role="$role" \
        --quiet 2>/dev/null || true
done

# Grant current user Artifact Registry access (for local docker push)
echo ""
echo -e "${BLUE}Granting current user Artifact Registry access...${NC}"
CURRENT_USER=$(gcloud config get-value account 2>/dev/null)
if [ -n "$CURRENT_USER" ]; then
    echo "  Granting roles/artifactregistry.writer to $CURRENT_USER..."
    gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
        --member="user:$CURRENT_USER" \
        --role="roles/artifactregistry.writer" \
        --quiet 2>/dev/null || true
fi

# Generate deploy.env for the main deploy script
echo ""
echo -e "${BLUE}Generating deploy.env...${NC}"
cat > deploy.env << EOF
GCP_PROJECT_ID=$GCP_PROJECT_ID
GCP_REGION=${GCP_REGION:-europe-west1}
GCP_LOCATION=${GCP_LOCATION:-europe-west1}
SERVICE_NAME=${SERVICE_NAME:-dataplex-business-ui}
ARTIFACT_REPO_NAME=${ARTIFACT_REPO_NAME:-dataplex-business-ui}
IMAGE_NAME=${IMAGE_NAME:-dataplex-business-ui}
OAUTH_CLIENT_ID=$OAUTH_CLIENT_ID
OAUTH_CLIENT_SECRET=$OAUTH_CLIENT_SECRET
ADMIN_EMAIL=$ADMIN_EMAIL
EXTERNAL_PROJECTS=$EXTERNAL_PROJECTS
EOF

# Handle external projects
if [ -n "$EXTERNAL_PROJECTS" ]; then
    echo ""
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}  EXTERNAL PROJECTS SETUP${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo ""
    echo -e "${GREEN}Service Account to share with external project admins:${NC}"
    echo "  $SERVICE_ACCOUNT"
    echo ""

    # Generate commands file for admins
    cat > external-projects-commands.sh << HEADER
#!/bin/bash
# ===========================================
# COMMANDS FOR EXTERNAL PROJECT ADMINS
# ===========================================
# Run these commands on each external project

SERVICE_ACCOUNT="$SERVICE_ACCOUNT"

HEADER

    for ext_project in $EXTERNAL_PROJECTS; do
        cat >> external-projects-commands.sh << COMMANDS
# --- Project: $ext_project ---
echo "Granting access on $ext_project..."

# Read table data
gcloud projects add-iam-policy-binding $ext_project \\
    --member="serviceAccount:\$SERVICE_ACCOUNT" \\
    --role="roles/bigquery.dataViewer" --quiet

# View table metadata
gcloud projects add-iam-policy-binding $ext_project \\
    --member="serviceAccount:\$SERVICE_ACCOUNT" \\
    --role="roles/bigquery.metadataViewer" --quiet

# Run queries (required for Conversational Analytics API)
gcloud projects add-iam-policy-binding $ext_project \\
    --member="serviceAccount:\$SERVICE_ACCOUNT" \\
    --role="roles/bigquery.jobUser" --quiet

# Modify dataset ACLs (required to grant access to users)
gcloud projects add-iam-policy-binding $ext_project \\
    --member="serviceAccount:\$SERVICE_ACCOUNT" \\
    --role="roles/bigquery.dataOwner" --quiet

# View Data Catalog entries
gcloud projects add-iam-policy-binding $ext_project \\
    --member="serviceAccount:\$SERVICE_ACCOUNT" \\
    --role="roles/datacatalog.viewer" --quiet

# View Data Lineage
gcloud projects add-iam-policy-binding $ext_project \\
    --member="serviceAccount:\$SERVICE_ACCOUNT" \\
    --role="roles/datalineage.viewer" --quiet

# CA API - create/use data agents for cross-project tables
gcloud projects add-iam-policy-binding $ext_project \\
    --member="serviceAccount:\$SERVICE_ACCOUNT" \\
    --role="roles/geminidataanalytics.dataAgentCreator" --quiet

gcloud projects add-iam-policy-binding $ext_project \\
    --member="serviceAccount:\$SERVICE_ACCOUNT" \\
    --role="roles/geminidataanalytics.dataAgentUser" --quiet

# Gemini for Google Cloud
gcloud projects add-iam-policy-binding $ext_project \\
    --member="serviceAccount:\$SERVICE_ACCOUNT" \\
    --role="roles/cloudaicompanion.user" --quiet

# Vertex AI access
gcloud projects add-iam-policy-binding $ext_project \\
    --member="serviceAccount:\$SERVICE_ACCOUNT" \\
    --role="roles/aiplatform.user" --quiet

# Grant users IAM access when requests are approved
gcloud projects add-iam-policy-binding $ext_project \\
    --member="serviceAccount:\$SERVICE_ACCOUNT" \\
    --role="roles/resourcemanager.projectIamAdmin" --quiet

COMMANDS
    done

    echo "echo 'Done!'" >> external-projects-commands.sh
    chmod +x external-projects-commands.sh

    echo -e "${YELLOW}Commands saved to: external-projects-commands.sh${NC}"
    echo ""
    read -p "Do you have admin access on external projects? Run commands now? (y/N): " confirm
    if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
        ./external-projects-commands.sh
    else
        echo ""
        echo "Send external-projects-commands.sh to each project admin."
    fi
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Next step - deploy the app:"
echo "  cd .."
echo "  ./deploy.sh --config deployment/deploy.env"
echo ""
