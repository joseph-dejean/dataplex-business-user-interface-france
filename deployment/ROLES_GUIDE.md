# Roles & Permissions Guide

This guide explains all the roles needed for the Dataplex Business UI to work.

---

## Quick Summary

| Who/What | Where | Roles Needed |
|----------|-------|--------------|
| Cloud Run Service Account | Your main project | Dataplex Admin, BigQuery Data Viewer, Firestore User, etc. |
| Cloud Run Service Account | External projects | BigQuery Data Viewer, Data Catalog Viewer |
| App Users | Inside the app | Viewer, Data Steward, or Admin |

---

## Part 1: GCP Project Roles (IAM)

### Finding Your Service Account

After deployment, your Cloud Run service account looks like:
```
PROJECT_NUMBER-compute@developer.gserviceaccount.com
```

To find it:
1. Go to: https://console.cloud.google.com/run
2. Click your service (dataplex-business-ui)
3. Look at "Service account" in the details

---

### Roles for Main Project (where app is deployed)

**How to grant (Console UI):**
1. Go to: https://console.cloud.google.com/iam-admin/iam
2. Click **"+ Grant Access"**
3. Paste the service account email
4. Add these roles:

| Role | Why it's needed |
|------|-----------------|
| `Dataplex Admin` | Search and view data catalog entries |
| `BigQuery Data Viewer` | View table data and metadata |
| `BigQuery Job User` | Run queries for sample data |
| `Data Catalog Viewer` | View catalog entries |
| `Cloud Datastore User` | Store access requests and app data |
| `Data Lineage Viewer` | Show upstream/downstream data flow |
| `Vertex AI User` | AI search and chat features |

---

### Roles for External Projects (where your data lives)

If your BigQuery tables are in a **different project**, that project's admin must grant access.

**How to grant (Console UI):**
1. Go to the external project's IAM page
2. Click **"+ Grant Access"**
3. Paste your Cloud Run service account email
4. Add these roles:

| Role | Why it's needed |
|------|-----------------|
| `BigQuery Data Viewer` | View tables |
| `BigQuery Metadata Viewer` | View table schemas |
| `Data Catalog Viewer` | Search tables in catalog |
| `Data Lineage Viewer` | View data lineage (optional) |

**Example:**
- Your app runs in: `dataplex-2-deploy`
- Your data is in: `dataplex-1-dataset`
- Service account: `123456789-compute@developer.gserviceaccount.com`

The admin of `dataplex-1-dataset` must add this service account with the roles above.

---

## Part 2: App Roles (Inside the Application)

The app has its own role system managed by the Admin.

### Available Roles

| Role | Can do |
|------|--------|
| **Viewer** | Search data, view metadata, request access |
| **Data Steward** | Everything Viewer can do + approve access requests for their datasets |
| **Admin** | Everything + manage users, approve all requests, configure app |

### How to Assign App Roles

1. Log in as Admin (the ADMIN_EMAIL you configured)
2. Go to **Admin Panel** (top right menu)
3. Click **"User Roles"**
4. Add user email and select their role

---

## Part 3: Dataplex Configuration

### Browse by Aspect

For the "Browse" feature to work, you need Dataplex aspects configured:

1. Go to: https://console.cloud.google.com/dataplex
2. Select your data lake
3. Go to **"Aspects"** or **"Entry Types"**
4. Make sure your tables have aspects attached

If you don't use aspects, the browse feature will be empty but search still works.

---

## Troubleshooting

### "No tables found"
- Check service account has BigQuery Data Viewer on the project where tables are
- Check Data Catalog Viewer role is granted
- Tables must be registered in Dataplex/Data Catalog

### "Access Denied" errors
- Check IAM roles in GCP Console
- Make sure you're using the correct service account

### "Can't approve access requests"
- Only Admin or Data Steward can approve
- Check your app role in Admin Panel

---

## Granting Roles via Console (Step-by-Step with Screenshots)

### Step 1: Open IAM
Go to: `https://console.cloud.google.com/iam-admin/iam?project=YOUR_PROJECT_ID`

### Step 2: Click Grant Access
Click the **"+ Grant Access"** button at the top.

### Step 3: Add Service Account
In "New principals" field, paste:
```
YOUR_PROJECT_NUMBER-compute@developer.gserviceaccount.com
```

### Step 4: Add Roles
Click "Select a role" and search for each role:
- Type "BigQuery Data Viewer" → select it
- Click "+ Add another role"
- Type "Data Catalog Viewer" → select it
- Continue for all needed roles

### Step 5: Save
Click **"Save"**

---

## Command Line Alternative

If you prefer terminal:

```bash
# Get your service account
gcloud run services describe dataplex-business-ui --region=europe-west1 --format="value(spec.template.spec.serviceAccountName)"

# Grant role on external project
gcloud projects add-iam-policy-binding EXTERNAL_PROJECT_ID \
  --member="serviceAccount:SERVICE_ACCOUNT_EMAIL" \
  --role="roles/bigquery.dataViewer"
```
