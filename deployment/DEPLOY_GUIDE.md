# Dataplex Business UI - Deployment Guide

## Step 1: Open Cloud Shell

1. Go to: https://console.cloud.google.com
2. Click the **Cloud Shell** icon (top right corner)
3. Wait for it to start

---

## Step 2: Clone the Repository

```bash
git clone https://github.com/joseph-dejean/tst1.git
cd tst1/deployment
```

---

## Step 3: Create OAuth Credentials

1. Go to: https://console.cloud.google.com/apis/credentials
2. Click **Create Credentials** → **OAuth client ID**
3. If asked, configure consent screen first (External, just your email)
4. Application type: **Web application**
5. Name: `Dataplex Business UI`
6. Authorized redirect URIs: `http://localhost:8080/auth/google/callback`
7. Click **Create**
8. **Copy** the Client ID and Client Secret (you'll need them next)

---

## Step 4: Create Your Config File

```bash
# Copy the example
cp config.env.example config.env

# Open editor
nano config.env
```

**Replace these values with yours:**

```bash
PROJECT_1=your-gcp-project-id
YOUR_EMAIL=your-email@gmail.com
ADMIN_EMAIL=your-email@gmail.com
EXTERNAL_PROJECTS=""
GCP_REGION=europe-west1
GCP_LOCATION=europe-west1
OAUTH_CLIENT_ID=paste-your-client-id-here.apps.googleusercontent.com
OAUTH_CLIENT_SECRET=paste-your-secret-here
```

**Save and exit:** `Ctrl+O` → `Enter` → `Ctrl+X`

> **Tip:** You can also click "Open Editor" in Cloud Shell for a visual editor.

---

## Step 5: Deploy

```bash
chmod +x quick-deploy.sh
./quick-deploy.sh
```

Wait for deployment to complete. You'll get a **Cloud Run URL** at the end.

---

## Step 6: Update OAuth Redirect URI

1. Go back to: https://console.cloud.google.com/apis/credentials
2. Click your **OAuth 2.0 Client ID**
3. Under **Authorized redirect URIs**, click **Add URI**
4. Add: `https://YOUR-CLOUD-RUN-URL/auth/google/callback`
5. Click **Save**

---

## Done!

Open your Cloud Run URL in the browser. You can now log in with Google.

---

## External Projects (Optional)

If you need to access BigQuery tables from other GCP projects:

1. Edit `config.env` and add:
   ```bash
   EXTERNAL_PROJECTS="other-project-1 other-project-2"
   ```

2. Run setup again - it will generate `external-projects-commands.sh`

3. Send that file to each external project's admin to run

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| OAuth redirect error | Add Cloud Run URL to OAuth redirect URIs |
| Permission denied | Check IAM roles were granted correctly |
| Can't see external tables | External project admin must run the commands |
