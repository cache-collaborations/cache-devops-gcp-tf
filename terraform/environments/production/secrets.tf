# terraform/environments/production/secrets.tf
# Secure secret management using Google Secret Manager

# Define all secrets
resource "google_secret_manager_secret" "production_secrets" {
  for_each = {
    "db-password"   = "Database password"
    "api-key"       = "API key for external services"
    "pubsub-key"    = "Authentication key for Pub/Sub"
    "tls-cert"      = "TLS certificate"
    "tls-key"       = "TLS private key"
    "jwt-secret"    = "Secret for JWT tokens"
  }

  secret_id = "${local.environment}-${each.key}"
  
  replication {
    automatic = true
  }
  
  labels = {
    environment = local.environment
    managed-by  = "terraform"
  }
}

# Store sensitive values securely without exposing in Terraform state
resource "null_resource" "update_secret_db_password" {
  triggers = {
    secret_value_hash = sha256(var.db_password)
  }
  
  provisioner "local-exec" {
    command = <<EOT
      echo -n '${var.db_password}' | gcloud secrets versions add ${local.environment}-db-password --data-file=- --project=${var.project_id}
    EOT
  }

  depends_on = [google_secret_manager_secret.production_secrets]
}

resource "null_resource" "update_secret_api_key" {
  triggers = {
    secret_value_hash = sha256(var.api_key)
  }
  
  provisioner "local-exec" {
    command = <<EOT
      echo -n '${var.api_key}' | gcloud secrets versions add ${local.environment}-api-key --data-file=- --project=${var.project_id}
    EOT
  }

  depends_on = [google_secret_manager_secret.production_secrets]
}

# Grant access to secrets for the application service account
resource "google_secret_manager_secret_iam_member" "app_sa_secret_access" {
  for_each = google_secret_manager_secret.production_secrets

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.kubernetes.app_service_account_email}"
}
