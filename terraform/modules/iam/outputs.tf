# Outputs
output "gke_sa_email" {
  value       = google_service_account.gke_sa.email
  description = "Email of the GKE service account"
}

output "app_sa_email" {
  value       = google_service_account.app_sa.email
  description = "Email of the application service account"
}

output "db_sa_email" {
  value       = google_service_account.db_sa.email
  description = "Email of the database service account"
}

output "audit_sa_email" {
  value       = google_service_account.audit_sa.email
  description = "Email of the audit service account"
}
