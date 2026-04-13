# ============================================
# Outputs - What Terraform Tells You After Running
# ============================================
# These are useful values that Terraform shows after deployment.

output "cloud_run_url" {
  description = "The URL of your deployed application"
  value       = google_cloud_run_v2_service.app.uri
}

output "service_account_email" {
  description = "The service account email used by Cloud Run"
  value       = google_service_account.cloud_run_sa.email
}

output "artifact_registry_repo" {
  description = "The Artifact Registry repository for Docker images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app_repo.repository_id}"
}

output "docker_push_command" {
  description = "Command to push your Docker image"
  value       = "docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app_repo.repository_id}/${var.app_name}:latest"
}

output "docker_build_command" {
  description = "Command to build your Docker image"
  value       = "docker build -t ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app_repo.repository_id}/${var.app_name}:latest ."
}

output "oauth_redirect_uri" {
  description = "Add this redirect URI to your Google OAuth credentials"
  value       = "${google_cloud_run_v2_service.app.uri}/auth/google/callback"
}
