# ============================================
# Variables - Your Configuration
# ============================================
# These are the values YOU need to provide.
# Either in terraform.tfvars or when running terraform apply.

variable "project_id" {
  description = "Your GCP Project ID (e.g., my-project-123)"
  type        = string
}

variable "region" {
  description = "GCP Region for Cloud Run and Artifact Registry (e.g., europe-west1)"
  type        = string
  default     = "europe-west1"
}

variable "app_name" {
  description = "Name for your application (used for Cloud Run service, etc.)"
  type        = string
  default     = "dataplex-business-ui"
}

# --- OAuth Configuration ---
variable "google_client_id" {
  description = "Google OAuth Client ID (from GCP Console > APIs & Services > Credentials)"
  type        = string
  sensitive   = true
}

variable "google_client_secret" {
  description = "Google OAuth Client Secret"
  type        = string
  sensitive   = true
}

# --- Admin Configuration ---
variable "admin_email" {
  description = "Admin email address (has full access)"
  type        = string
}

# --- Optional: External Projects ---
variable "external_projects" {
  description = "Space-separated list of external project IDs where your data lives"
  type        = string
  default     = ""
}

# --- Optional: Email (SMTP) ---
variable "smtp_email" {
  description = "SMTP email for notifications (optional)"
  type        = string
  default     = ""
}

variable "smtp_password" {
  description = "SMTP password/app password (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

# --- Docker Image ---
variable "docker_image_tag" {
  description = "Docker image tag to deploy (default: latest)"
  type        = string
  default     = "latest"
}
