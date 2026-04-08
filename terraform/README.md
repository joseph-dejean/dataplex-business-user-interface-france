# Terraform Deployment for Dataplex Business UI

## What is Terraform?

Think of Terraform like a **recipe** for your cloud infrastructure:

```
Script (bash/gcloud):          Terraform:
─────────────────────          ──────────
"Do step 1"                    "I want this end result"
"Do step 2"                    (Terraform figures out the steps)
"Do step 3"
```

**Benefits:**
- Run it 100 times = same result (no duplicates)
- `terraform destroy` = removes everything it created
- `terraform plan` = shows what will change BEFORE doing it
- Works across teams (everyone uses same config)

---

## Prerequisites

1. **Install Terraform** (one-time setup):
   ```bash
   # Windows (with Chocolatey)
   choco install terraform

   # Mac
   brew install terraform

   # Or download from: https://www.terraform.io/downloads
   ```

2. **Install Google Cloud SDK** (if not already):
   ```bash
   # Download from: https://cloud.google.com/sdk/docs/install
   ```

3. **Login to GCP**:
   ```bash
   gcloud auth application-default login
   ```

---

## Step-by-Step Deployment

### Step 1: Configure Your Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
```hcl
project_id           = "my-gcp-project"
region               = "europe-west1"
google_client_id     = "123456789-xxx.apps.googleusercontent.com"
google_client_secret = "GOCSPX-xxx"
admin_email          = "admin@example.com"
```

### Step 2: Initialize Terraform

```bash
terraform init
```

This downloads the required providers (like installing dependencies).

### Step 3: Preview Changes

```bash
terraform plan
```

This shows what Terraform WILL create (without doing it yet).

### Step 4: Apply Changes

```bash
terraform apply
```

Type `yes` when prompted. Terraform will create:
- Artifact Registry repository
- Service Account with IAM roles
- Cloud Run service

### Step 5: Build and Push Docker Image

After Terraform creates the infrastructure, you need to push your Docker image:

```bash
# Go back to project root
cd ..

# Configure Docker to use GCP
gcloud auth configure-docker europe-west1-docker.pkg.dev

# Build the image
docker build -t europe-west1-docker.pkg.dev/YOUR_PROJECT_ID/dataplex-business-ui-repo/dataplex-business-ui:latest .

# Push the image
docker push europe-west1-docker.pkg.dev/YOUR_PROJECT_ID/dataplex-business-ui-repo/dataplex-business-ui:latest
```

### Step 6: Deploy New Version

After pushing, update Cloud Run:

```bash
cd terraform
terraform apply
```

---

## Common Commands

| Command | What it does |
|---------|--------------|
| `terraform init` | Initialize (run once) |
| `terraform plan` | Preview changes |
| `terraform apply` | Create/update resources |
| `terraform destroy` | Delete everything |
| `terraform output` | Show outputs (URLs, etc.) |

---

## File Structure

```
terraform/
├── main.tf              # Main resources (Cloud Run, Service Account, etc.)
├── variables.tf         # Input variables definition
├── outputs.tf           # Output values (URLs, commands)
├── terraform.tfvars     # YOUR configuration (don't commit!)
└── README.md            # This file
```

---

## Troubleshooting

### "Error: Permission denied"
```bash
gcloud auth application-default login
```

### "Error: API not enabled"
Terraform enables APIs automatically, but it may take a few minutes.
Wait and try again.

### "Error: Docker image not found"
You need to build and push the Docker image first (see Step 5).

---

## Updating Your App

When you make code changes:

1. Build new Docker image:
   ```bash
   docker build -t europe-west1-docker.pkg.dev/PROJECT_ID/dataplex-business-ui-repo/dataplex-business-ui:v2 .
   docker push europe-west1-docker.pkg.dev/PROJECT_ID/dataplex-business-ui-repo/dataplex-business-ui:v2
   ```

2. Update terraform.tfvars:
   ```hcl
   docker_image_tag = "v2"
   ```

3. Apply:
   ```bash
   terraform apply
   ```

Or keep using Cloud Build for automatic deployments (your existing `cloudbuild.yaml` still works!).
