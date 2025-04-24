# terraform/modules/audit/main.tf

# Create log sink for all audit logs
resource "google_logging_project_sink" "audit_logs_sink" {
  name        = "${var.environment}-audit-logs-sink"
  description = "Sink for collecting all audit logs for SOC 2 compliance"
  
  # Destination can be BigQuery, Cloud Storage, Pub/Sub, or another project
  destination = "storage.googleapis.com/${google_storage_bucket.audit_logs.name}"
  
  # Filter for audit logs
  filter = "logName:\"cloudaudit.googleapis.com%2Factivity\" OR logName:\"cloudaudit.googleapis.com%2Fsystem_event\" OR logName:\"cloudaudit.googleapis.com%2Fdata_access\""
  
  # Use a unique writer identity
  unique_writer_identity = true
}

# Storage bucket for audit logs
resource "google_storage_bucket" "audit_logs" {
  name          = "${var.project_id}-${var.environment}-audit-logs"
  location      = var.region
  force_destroy = false
  
  uniform_bucket_level_access = true
  
  # Configure retention policy for SOC 2 compliance
  retention_policy {
    is_locked = true
    retention_period = 7776000 # 90 days in seconds
  }
  
  lifecycle_rule {
    condition {
      age = 365 # days
    }
    action {
      type = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  versioning {
    enabled = true
  }
  
  encryption {
    default_kms_key_name = google_kms_crypto_key.audit_logs_key.id
  }
}

# KMS key for encryption of audit logs
resource "google_kms_key_ring" "audit_key_ring" {
  name     = "${var.environment}-audit-keyring"
  location = var.region
}

resource "google_kms_crypto_key" "audit_logs_key" {
  name            = "${var.environment}-audit-key"
  key_ring        = google_kms_key_ring.audit_key_ring.id
  rotation_period = "7776000s" # 90 days in seconds
  
  # Prevent destruction for SOC 2 compliance
  lifecycle {
    prevent_destroy = true
  }
}

# Grant permissions to the log sink service account
resource "google_storage_bucket_iam_member" "log_writer" {
  bucket = google_storage_bucket.audit_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.audit_logs_sink.writer_identity
}

# Create log metrics for security monitoring
resource "google_logging_metric" "iam_changes" {
  name        = "${var.environment}_iam_changes"
  description = "Count of IAM permission changes for SOC 2 monitoring"
  filter      = "resource.type=project AND protoPayload.methodName=(\"SetIamPolicy\" OR \"modifyPolicy\")"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key         = "resource_type"
      value_type  = "STRING"
      description = "Type of resource for which IAM policy is modified"
    }
  }
  label_extractors = {
    "resource_type" = "EXTRACT(protoPayload.resourceName)"
  }
}

resource "google_logging_metric" "vpc_network_changes" {
  name        = "${var.environment}_vpc_network_changes"
  description = "Count of VPC network changes for SOC 2 monitoring"
  filter      = "resource.type=(gce_network OR gce_firewall) AND protoPayload.methodName:(\"compute.networks\" OR \"compute.firewalls\")"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# Create alerting policies for security events
resource "google_monitoring_alert_policy" "iam_changes_alert" {
  display_name = "${var.environment} IAM Changes Alert"
  combiner     = "OR"
  conditions {
    display_name = "IAM policy changes"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.iam_changes.name}\" AND resource.type=\"global\""
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      trigger {
        count = 1
      }
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.type"]
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
  
  documentation {
    content   = "IAM policy changes detected. This could indicate unauthorized access or changes to permissions."
    mime_type = "text/markdown"
  }
}

# Notification channel for alerts
resource "google_monitoring_notification_channel" "email" {
  display_name = "SOC 2 Compliance Team"
  type         = "email"
  labels = {
    email_address = var.security_email
  }
}
