# ============================================
# Terraform Configuration for Dataplex Business UI
# ============================================
# This file describes ALL the GCP resources needed for your app.
# Terraform will create them if they don't exist,
# or update them if they changed.

# --- Terraform Settings ---
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Optional: Store state in GCS bucket (recommended for teams)
  # Uncomment and configure if you want remote state
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "dataplex-business-ui"
  # }
}

# --- Google Cloud Provider ---
provider "google" {
  project = var.project_id
  region  = var.region
}

# --- Enable Required APIs ---
# Terraform will enable these APIs if not already enabled
resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",              # Cloud Run
    "artifactregistry.googleapis.com", # Artifact Registry (Docker images)
    "cloudbuild.googleapis.com",       # Cloud Build
    "iam.googleapis.com",              # IAM
    "dataplex.googleapis.com",         # Dataplex
    "datacatalog.googleapis.com",      # Data Catalog
    "bigquery.googleapis.com",         # BigQuery
    "datalineage.googleapis.com",      # Data Lineage
    "aiplatform.googleapis.com",       # Vertex AI (Gemini)
  ])

  service            = each.key
  disable_on_destroy = false
}

# --- Artifact Registry Repository ---
# This is where Docker images are stored
resource "google_artifact_registry_repository" "app_repo" {
  location      = var.region
  repository_id = "${var.app_name}-repo"
  description   = "Docker repository for ${var.app_name}"
  format        = "DOCKER"

  depends_on = [google_project_service.required_apis]
}

# --- Service Account ---
# Cloud Run will use this identity to access GCP resources
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${var.app_name}-sa"
  display_name = "Service Account for ${var.app_name}"
  description  = "Used by Cloud Run to access Dataplex, BigQuery, etc."

  depends_on = [google_project_service.required_apis]
}

# --- IAM Roles for Service Account ---
# These are the permissions the app needs
resource "google_project_iam_member" "sa_roles" {
  for_each = toset([
    "roles/dataplex.viewer",                        # View Dataplex resources
    "roles/dataplex.catalogEditor",                 # Edit catalog entries
    "roles/datacatalog.viewer",                     # View Data Catalog
    "roles/bigquery.dataViewer",                    # Read BigQuery data
    "roles/bigquery.metadataViewer",                # View BigQuery metadata
    "roles/bigquery.jobUser",                       # Run BigQuery jobs
    "roles/bigquery.dataOwner",                     # Grant access to users
    "roles/datalineage.viewer",                     # View Data Lineage
    "roles/aiplatform.user",                        # Use Vertex AI (Gemini)
    "roles/geminidataanalytics.dataAgentCreator",   # CA API - create agents
    "roles/geminidataanalytics.dataAgentUser",      # CA API - use agents
    "roles/cloudaicompanion.user",                  # Gemini for Google Cloud
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# --- Cloud Run Service ---
# This is your actual application
resource "google_cloud_run_v2_service" "app" {
  name     = var.app_name
  location = var.region

  template {
    # Use our service account
    service_account = google_service_account.cloud_run_sa.email

    containers {
      # Docker image from Artifact Registry
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app_repo.repository_id}/${var.app_name}:${var.docker_image_tag}"

      ports {
        container_port = 8080
      }

      # Environment variables
      env {
        name  = "VITE_API_URL"
        value = "/api"
      }
      env {
        name  = "VITE_API_VERSION"
        value = "v1"
      }
      env {
        name  = "VITE_GOOGLE_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GOOGLE_CLOUD_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }
      env {
        name  = "GCP_LOCATION"
        value = var.region
      }
      env {
        name  = "GCP_REGION"
        value = var.region
      }
      env {
        name  = "VITE_GOOGLE_CLIENT_ID"
        value = var.google_client_id
      }
      env {
        name  = "VITE_GOOGLE_CLIENT_SECRET"
        value = var.google_client_secret
      }
      env {
        name  = "VITE_GOOGLE_REDIRECT_URI"
        value = "/auth/google/callback"
      }
      env {
        name  = "SUPER_ADMIN_EMAIL"
        value = var.admin_email
      }
      env {
        name  = "VITE_ADMIN_EMAIL"
        value = var.admin_email
      }
      env {
        name  = "EXTERNAL_PROJECTS"
        value = var.external_projects
      }
      env {
        name  = "PORT"
        value = "8080"
      }

      # Optional SMTP
      dynamic "env" {
        for_each = var.smtp_email != "" ? [1] : []
        content {
          name  = "SMTP_EMAIL"
          value = var.smtp_email
        }
      }
      dynamic "env" {
        for_each = var.smtp_password != "" ? [1] : []
        content {
          name  = "SMTP_PASSWORD"
          value = var.smtp_password
        }
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "1Gi"
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
  }

  # Allow traffic from the internet
  ingress = "INGRESS_TRAFFIC_ALL"

  depends_on = [
    google_project_service.required_apis,
    google_artifact_registry_repository.app_repo,
    google_project_iam_member.sa_roles,
  ]
}

# --- Allow Unauthenticated Access ---
# This makes the app publicly accessible (users login via Google OAuth)
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  location = google_cloud_run_v2_service.app.location
  name     = google_cloud_run_v2_service.app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- Cloud Build Trigger (Optional) ---
# Automatically builds and deploys when you push to GitHub
# Uncomment if you want automatic deployments
# resource "google_cloudbuild_trigger" "deploy_trigger" {
#   name        = "${var.app_name}-deploy"
#   description = "Build and deploy ${var.app_name} on push to main"
#
#   github {
#     owner = "your-github-username"
#     name  = "dataplex-business-user-interface"
#     push {
#       branch = "^main$"
#     }
#   }
#
#   filename = "cloudbuild.yaml"
#
#   substitutions = {
#     _REGION        = var.region
#     _REPO_NAME     = google_artifact_registry_repository.app_repo.repository_id
#     _APP_NAME      = var.app_name
#     _SERVICE_NAME  = var.app_name
#     _ADMIN_EMAIL   = var.admin_email
#     _CLIENT_ID     = var.google_client_id
#     _CLIENT_SECRET = var.google_client_secret
#     _GCP_LOCATION  = var.region
#     _GCP_REGION    = var.region
#   }
# }
