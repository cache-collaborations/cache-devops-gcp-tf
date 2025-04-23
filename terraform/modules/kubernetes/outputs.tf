# terraform/modules/kubernetes/outputs.tf
output "cluster_name" {
  value       = google_container_cluster.primary.name
  description = "The name of the GKE cluster"
}

output "cluster_endpoint" {
  value       = google_container_cluster.primary.endpoint
  description = "The IP address of the GKE cluster"
}

output "cluster_ca_certificate" {
  value       = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  description = "The CA certificate of the GKE cluster"
  sensitive   = true
}

output "app_service_account_email" {
  value       = google_service_account.app_sa.email
  description = "The email of the application service account"
}

output "gke_service_account_email" {
  value       = google_service_account.gke_sa.email
  description = "The email of the GKE service account"
}
