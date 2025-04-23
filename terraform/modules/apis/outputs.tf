# terraform/modules/apis/outputs.tf
output "enabled_apis" {
  value       = [for api in google_project_service.gcp_services : api.service]
  description = "List of enabled APIs"
}
