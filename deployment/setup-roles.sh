#!/bin/bash
# ===========================================
# DATAPLEX BUSINESS UI - IAM SETUP SCRIPT
# ===========================================
# Supports multiple external projects!

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
if [ -z "$PROJECT_1" ] || [ "$PROJECT_1" == "your-main-project-id" ]; then
    echo -e "${RED}ERROR: PROJECT_1 is not set in config.env${NC}"
    exit 1
fi

if [ -z "$YOUR_EMAIL" ] || [ "$YOUR_EMAIL" == "your-email@example.com" ]; then
    echo -e "${RED}ERROR: YOUR_EMAIL is not set in config.env${NC}"
    exit 1
fi

if [ -z "$OAUTH_CLIENT_ID" ] || [ "$OAUTH_CLIENT_ID" == "your-client-id.apps.googleusercontent.com" ]; then
    echo -e "${RED}ERROR: OAUTH_CLIENT_ID is not set!${NC}"
    echo "Create OAuth credentials at: https://console.cloud.google.com/apis/credentials"
    exit 1
fi

echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Main Project:       $PROJECT_1"
echo "  External Projects:  ${EXTERNAL_PROJECTS:-None}"
echo "  Your Email:         $YOUR_EMAIL"
echo "  Admin Email:        $ADMIN_EMAIL"
echo ""

# Set the project
echo -e "${BLUE}[1/5] Setting active project to $PROJECT_1...${NC}"
gcloud config set project $PROJECT_1

# Get project number
echo -e "${BLUE}[2/5] Getting project info...${NC}"
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_1 --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo "  Project Number:    $PROJECT_NUMBER"
echo "  Service Account:   $SERVICE_ACCOUNT"

# Enable APIs
echo ""
echo -e "${BLUE}[3/5] Enabling required APIs...${NC}"
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
)

for api in "${APIS[@]}"; do
    echo "  Enabling $api..."
    gcloud services enable $api --quiet 2>/dev/null || true
done

# Grant roles to user
echo ""
echo -e "${BLUE}[4/5] Granting deployment roles to $YOUR_EMAIL...${NC}"

USER_ROLES=(
    "roles/run.admin"
    "roles/iam.serviceAccountUser"
    "roles/artifactregistry.admin"
    "roles/cloudbuild.builds.editor"
    "roles/datastore.owner"
    "roles/serviceusage.serviceUsageAdmin"
)

for role in "${USER_ROLES[@]}"; do
    echo "  Granting $role..."
    gcloud projects add-iam-policy-binding $PROJECT_1 \
        --member="user:$YOUR_EMAIL" \
        --role="$role" \
        --quiet 2>/dev/null || true
done

# Grant roles to service account
echo ""
echo -e "${BLUE}[5/5] Granting runtime roles to service account...${NC}"

SA_ROLES=(
    "roles/dataplex.admin"
    "roles/bigquery.dataViewer"
    "roles/bigquery.metadataViewer"
    "roles/bigquery.jobUser"
    "roles/datacatalog.viewer"
    "roles/datastore.user"
    "roles/datalineage.viewer"
    "roles/aiplatform.user"
    "roles/resourcemanager.projectIamAdmin"
)

for role in "${SA_ROLES[@]}"; do
    echo "  Granting $role..."
    gcloud projects add-iam-policy-binding $PROJECT_1 \
        --member="serviceAccount:$SERVICE_ACCOUNT" \
        --role="$role" \
        --quiet 2>/dev/null || true
done

# Generate deploy.env
echo ""
echo -e "${BLUE}Generating deploy.env...${NC}"
cat > deploy.env << EOF
GCP_PROJECT_ID=$PROJECT_1
GCP_REGION=${GCP_REGION:-europe-west1}
GCP_LOCATION=${GCP_LOCATION:-europe-west1}
SERVICE_NAME=${SERVICE_NAME:-dataplex-business-ui}
ARTIFACT_REPO_NAME=${ARTIFACT_REPO_NAME:-dataplex-business-ui}
IMAGE_NAME=${IMAGE_NAME:-dataplex-business-ui}
OAUTH_CLIENT_ID=$OAUTH_CLIENT_ID
OAUTH_CLIENT_SECRET=$OAUTH_CLIENT_SECRET
ADMIN_EMAIL=$ADMIN_EMAIL
EOF

# Handle external projects
if [ -n "$EXTERNAL_PROJECTS" ] && [ "$EXTERNAL_PROJECTS" != "external-project-1 external-project-2" ]; then
    echo ""
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}  EXTERNAL PROJECTS SETUP${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo ""
    echo "Your app's service account needs access to these external projects."
    echo ""
    echo -e "${GREEN}Service Account to share:${NC}"
    echo "  $SERVICE_ACCOUNT"
    echo ""

    # Generate commands file for admins
    cat > external-projects-commands.sh << 'HEADER'
#!/bin/bash
# ===========================================
# COMMANDS FOR EXTERNAL PROJECT ADMINS
# ===========================================
# Run these commands on each external project

HEADER

    echo "SERVICE_ACCOUNT=\"$SERVICE_ACCOUNT\"" >> external-projects-commands.sh
    echo "" >> external-projects-commands.sh

    for ext_project in $EXTERNAL_PROJECTS; do
        echo "# --- Commands for project: $ext_project ---" >> external-projects-commands.sh
        echo "PROJECT=\"$ext_project\"" >> external-projects-commands.sh
        cat >> external-projects-commands.sh << 'COMMANDS'

gcloud projects add-iam-policy-binding $PROJECT \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/bigquery.dataViewer"

gcloud projects add-iam-policy-binding $PROJECT \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/bigquery.metadataViewer"

gcloud projects add-iam-policy-binding $PROJECT \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/datacatalog.viewer"

gcloud projects add-iam-policy-binding $PROJECT \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/datalineage.viewer"

echo "Done for $PROJECT"

COMMANDS
        echo "" >> external-projects-commands.sh
    done

    echo -e "${YELLOW}Commands saved to: external-projects-commands.sh${NC}"
    echo ""
    echo "Options:"
    echo "  1. If YOU have admin access on external projects, run:"
    echo "     ./external-projects-commands.sh"
    echo ""
    echo "  2. If you DON'T have admin access, send the file to each project admin"
    echo ""
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
