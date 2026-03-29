# Dataplex Business UI - Easy Deployment Guide

## Quick Start (3 Steps)

### Step 1: Create your config.env

```bash
# Copy the example file
cp config.env.example config.env

# Edit with your values
nano config.env
```

**Your config.env is private** - it's in .gitignore and won't be pushed to GitHub.

**Required values:**
| Variable | What to put |
|----------|-------------|
| `PROJECT_1` | Your GCP project ID (where app runs) |
| `YOUR_EMAIL` | Your Google email |
| `ADMIN_EMAIL` | Who manages the app |
| `OAUTH_CLIENT_ID` | From GCP Console (see below) |
| `OAUTH_CLIENT_SECRET` | From GCP Console (see below) |

**For multiple external projects:**
```bash
EXTERNAL_PROJECTS="project-a project-b project-c"
```

---

### Step 2: Create OAuth Credentials

1. Go to: https://console.cloud.google.com/apis/credentials
2. **Create Credentials** > **OAuth client ID**
3. Type: **Web application**
4. Name: `Dataplex Business UI`
5. Redirect URI: `http://localhost:8080/auth/google/callback`
6. Copy **Client ID** and **Secret** to `config.env`

---

### Step 3: Run Quick Deploy

```bash
chmod +x quick-deploy.sh
./quick-deploy.sh
```

Done! You'll get a Cloud Run URL.

---

## After Deployment

### Add OAuth Redirect URI

Go back to OAuth credentials and add:
```
https://YOUR_CLOUD_RUN_URL/auth/google/callback
```

---

## Multiple External Projects

If you need to access BigQuery tables from other GCP projects:

### Option A: You have admin access
The setup script will offer to grant access automatically.

### Option B: You don't have admin access
1. The script generates `external-projects-commands.sh`
2. Send this file to each project admin
3. They run it to grant your app access

### What admins need to do:
```bash
# Replace with your service account (shown during setup)
SERVICE_ACCOUNT="123456789-compute@developer.gserviceaccount.com"
PROJECT="their-project-id"

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
```

---

## Summary

| What | Where | Who |
|------|-------|-----|
| App runs | PROJECT_1 | You (full access) |
| BigQuery data | External projects | Admin grants access |
| OAuth | PROJECT_1 | You create credentials |
| Admin panel | App UI | ADMIN_EMAIL user |

---

## Troubleshooting

### "Permission denied" errors
- Make sure all APIs are enabled
- Check service account has correct roles
- For external projects, confirm admin ran the commands

### OAuth redirect error
- Add the Cloud Run URL to OAuth authorized redirect URIs
- Format: `https://your-app-xxxxx.run.app/auth/google/callback`

### Can't see external project tables
- External project admin needs to grant roles to your service account
- Use `external-projects-commands.sh` generated during setup
