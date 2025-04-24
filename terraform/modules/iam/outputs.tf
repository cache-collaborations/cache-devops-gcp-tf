# Output service account emails
output "gke_service_account_email" {
  value = google_service_account.gke_service_account.email
}

output "app_service_account_email" {
  value = google_service_account.app_service_account.email
}

output "monitoring_service_account_email" {
  value = google_service_account.monitoring_service_account.email
}
