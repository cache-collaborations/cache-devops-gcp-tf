# terraform/modules/iam/main.tf

# Create service accounts for different components
resource "google_service_account" "gke_sa" {
  account_id   = "${var.prefix}-${var.environment}-gke-sa"
  display_name = "${var.environment} GKE Service Account"
  project      = var.project_id
  description  = "Service account for GKE nodes with strict least privilege permissions"
}

resource "google_service_account" "app_sa" {
  account_id   = "${var.prefix}-${var.environment}-app-sa"
  display_name = "Application Service Account for ${var.environment}"
  project      = var.project_id
  description  = "Service account for application with minimal required permissions"
}

resource "google_service_account" "db_sa" {
  account_id   = "${var.prefix}-${var.environment}-db-sa"
  display_name = "Database Service Account for ${var.environment}"
  project      = var.project_id
  description  = "Service account for database operations"
}

resource "google_service_account" "audit_sa" {
  account_id   = "${var.prefix}-${var.environment}-audit-sa"
  display_name = "Audit Service Account for ${var.environment}"
  project      = var.project_id
  description  = "Service account for audit log shipping and monitoring"
}

# Assign roles using least privilege principle
resource "google_project_iam_member" "gke_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/storage.objectViewer",
    "roles/artifactregistry.reader"
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_project_iam_member" "app_sa_roles" {
  for_each = toset([
    "roles/secretmanager.secretAccessor",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.app_sa.email}"
}

resource "google_project_iam_member" "db_sa_roles" {
  for_each = toset([
    "roles/cloudsql.client"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.db_sa.email}"
}

resource "google_project_iam_member" "audit_sa_roles" {
  for_each = toset([
    "roles/logging.viewer",
    "roles/logging.configWriter",
    "roles/monitoring.viewer"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.audit_sa.email}"
}

# Custom role for SOC 2 auditors with minimum required permissions
resource "google_project_iam_custom_role" "soc2_auditor" {
  role_id     = "soc2Auditor"
  title       = "SOC2 Auditor"
  description = "Custom role for SOC 2 auditors with read-only access to audit logs"
  permissions = [
    "logging.logEntries.list",
    "logging.logs.list",
    "logging.views.get",
    "logging.views.list",
    "monitoring.timeSeries.list",
    "resourcemanager.projects.get"
  ]
  project = var.project_id
}

# Workload Identity binding for Kubernetes
resource "google_service_account_iam_binding" "workload_identity_binding" {
  service_account_id = google_service_account.app_sa.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.environment}/app]"
  ]
}
