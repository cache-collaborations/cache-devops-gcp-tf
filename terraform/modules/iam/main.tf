# terraform/modules/iam/main.tf

# Service accounts with least privilege access
resource "google_service_account" "gke_service_account" {
  account_id   = "${var.environment}-gke-sa"
  display_name = "${var.environment} GKE Service Account"
  description  = "Service account for GKE nodes with least privilege"
  project      = var.project_id
}

resource "google_service_account" "app_service_account" {
  account_id   = "${var.environment}-app-sa"
  display_name = "${var.environment} Application Service Account"
  description  = "Service account for application workloads"
  project      = var.project_id
}

resource "google_service_account" "monitoring_service_account" {
  account_id   = "${var.environment}-monitoring-sa"
  display_name = "${var.environment} Monitoring Service Account"
  description  = "Service account for monitoring and audit logging"
  project      = var.project_id
}

# IAM role bindings for GKE service account - minimal required permissions
resource "google_project_iam_member" "gke_node_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/storage.objectViewer",
    "roles/artifactregistry.reader"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_service_account.email}"
}

# IAM role bindings for application service account
resource "google_project_iam_member" "app_roles" {
  for_each = toset([
    "roles/secretmanager.secretAccessor",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber",
    "roles/cloudsql.client"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.app_service_account.email}"
}

# IAM role bindings for monitoring service account
resource "google_project_iam_member" "monitoring_roles" {
  for_each = toset([
    "roles/logging.viewer",
    "roles/logging.configWriter", 
    "roles/monitoring.admin",
    "roles/stackdriver.resourceMetadata.writer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.monitoring_service_account.email}"
}

# Custom role for audit log viewing only
resource "google_project_iam_custom_role" "audit_viewer" {
  role_id     = "auditLogViewer"
  title       = "Audit Log Viewer"
  description = "Custom role for SOC 2 compliance with access to audit logs only"
  permissions = [
    "logging.logEntries.list",
    "logging.logs.list",
    "logging.views.access",
    "logging.views.list",
    "resourcemanager.projects.get"
  ]
  project = var.project_id
}

# Workload Identity configuration
resource "google_service_account_iam_binding" "workload_identity_binding" {
  service_account_id = google_service_account.app_service_account.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.environment}/app]"
  ]
}
