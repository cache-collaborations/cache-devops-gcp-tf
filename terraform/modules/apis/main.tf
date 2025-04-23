# terraform/modules/apis/main.tf
resource "google_project_service" "gcp_services" {
  for_each = toset(var.services)
  
  project = var.project_id
  service = each.value

  disable_dependent_services = true
  disable_on_destroy         = false
}
