# SOC 2 Audit Module for comprehensive logging and monitoring

# Create a dedicated log bucket for audit logs with proper retention
resource "google_logging_project_bucket_config" "audit_logs" {
  project        = var.project_id
  location       = var.region
  retention_days = 365  # Retain logs for 1 year for SOC 2 compliance
  bucket_id      = "${var.prefix}-${var.environment}-audit-logs"
  
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 365
    }
  }
  
  # Enable CMEK encryption for security
  encryption_config {
    kms_key_name = google_kms_crypto_key.audit_key.id
  }
}

# KMS key for encrypting audit logs
resource "google_kms_key_ring" "audit_keyring" {
  name     = "${var.prefix}-${var.environment}-audit-keyring"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "audit_key" {
  name            = "${var.prefix}-${var.environment}-audit-key"
  key_ring        = google_kms_key_ring.audit_keyring.id
  rotation_period = "2592000s"  # 30 days
  
  lifecycle {
    prevent_destroy = true
  }
}

# Create log sinks for different audit log types
resource "google_logging_project_sink" "admin_activity" {
  name        = "${var.prefix}-${var.environment}-admin-activity-sink"
  destination = "logging.googleapis.com/projects/${var.project_id}/locations/${var.region}/buckets/${google_logging_project_bucket_config.audit_logs.bucket_id}"
  filter      = "logName:\"cloudaudit.googleapis.com/activity\""

  unique_writer_identity = true
}

resource "google_logging_project_sink" "data_access" {
  name        = "${var.prefix}-${var.environment}-data-access-sink"
  destination = "logging.googleapis.com/projects/${var.project_id}/locations/${var.region}/buckets/${google_logging_project_bucket_config.audit_logs.bucket_id}"
  filter      = "logName:\"cloudaudit.googleapis.com/data_access\""

  unique_writer_identity = true
}

resource "google_logging_project_sink" "system_events" {
  name        = "${var.prefix}-${var.environment}-system-events-sink"
  destination = "logging.googleapis.com/projects/${var.project_id}/locations/${var.region}/buckets/${google_logging_project_bucket_config.audit_logs.bucket_id}"
  filter      = "logName:\"cloudaudit.googleapis.com/system_event\""

  unique_writer_identity = true
}

# Create log-based metrics for security monitoring
resource "google_logging_metric" "iam_changes" {
  name        = "${var.prefix}_${var.environment}_iam_changes"
  description = "Counts of IAM policy changes for SOC 2 compliance monitoring"
  filter      = "resource.type=project AND protoPayload.serviceName=iam.googleapis.com AND protoPayload.methodName=(\"SetIamPolicy\" OR \"modifyPolicy\")"
  
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key         = "resource_type"
      value_type  = "STRING"
      description = "Type of resource for which IAM policy was changed"
    }
  }
  
  label_extractors = {
    "resource_type" = "EXTRACT(protoPayload.resourceName)"
  }
}

resource "google_logging_metric" "auth_failures" {
  name        = "${var.prefix}_${var.environment}_auth_failures"
  description = "Counts of authentication failures for SOC 2 compliance monitoring"
  filter      = "protoPayload.methodName=\"google.cloud.identitytoolkit.v1.Authentication\" AND protoPayload.status.code=16"
  
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_logging_metric" "network_changes" {
  name        = "${var.prefix}_${var.environment}_network_changes"
  description = "Counts of network configuration changes for SOC 2 compliance monitoring"
  filter      = "resource.type=(gce_network OR gce_firewall) AND protoPayload.methodName=(\"compute.networks\" OR \"compute.firewalls\")"
  
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# Create alert policies for security monitoring
resource "google_monitoring_alert_policy" "iam_change_alert" {
  display_name = "${var.prefix}-${var.environment}-iam-change-alert"
  combiner     = "OR"
  
  conditions {
    display_name = "IAM Policy Changes"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.iam_changes.name}\" AND resource.type=\"global\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      
      trigger {
        count = 1
      }
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.name]
  
  documentation {
    content   = "IAM policy changes detected in project ${var.project_id} (${var.environment} environment). Please investigate to ensure changes are authorized."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "auth_failure_alert" {
  display_name = "${var.prefix}-${var.environment}-auth-failure-alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Authentication Failures"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.auth_failures.name}\" AND resource.type=\"global\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      
      trigger {
        count = 1
      }
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.name]
  
  documentation {
    content   = "Multiple authentication failures detected in project ${var.project_id} (${var.environment} environment). This may indicate a brute force attempt."
    mime_type = "text/markdown"
  }
}

# Create notification channels
resource "google_monitoring_notification_channel" "email" {
  display_name = "${var.prefix}-${var.environment}-security-email"
  type         = "email"
  
  labels = {
    email_address = var.security_email
  }
  
  user_labels = {
    environment = var.environment
  }
}

# Create a dashboard for SOC 2 compliance monitoring
resource "google_monitoring_dashboard" "soc2_dashboard" {
  dashboard_json = <<EOF
{
  "displayName": "${var.prefix}-${var.environment}-soc2-compliance-dashboard",
  "gridLayout": {
    "widgets": [
      {
        "title": "IAM Policy Changes",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"logging.googleapis.com/user/${google_logging_metric.iam_changes.name}\" AND resource.type=\"global\"",
                "aggregation": {
                  "perSeriesAligner": "ALIGN_RATE",
                  "crossSeriesReducer": "REDUCE_SUM",
                  "groupByFields": []
                }
              }
            },
            "plotType": "LINE"
          }],
          "timeshiftDuration": "0s",
          "yAxis": {
            "label": "Changes",
            "scale": "LINEAR"
          }
        }
      },
      {
        "title": "Authentication Failures",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"logging.googleapis.com/user/${google_logging_metric.auth_failures.name}\" AND resource.type=\"global\"",
                "aggregation": {
                  "perSeriesAligner": "ALIGN_RATE",
                  "crossSeriesReducer": "REDUCE_SUM",
                  "groupByFields": []
                }
              }
            },
            "plotType": "LINE"
          }],
          "timeshiftDuration": "0s",
          "yAxis": {
            "label": "Failures",
            "scale": "LINEAR"
          }
        }
      },
      {
        "title": "Network Changes",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"logging.googleapis.com/user/${google_logging_metric.network_changes.name}\" AND resource.type=\"global\"",
                "aggregation": {
                  "perSeriesAligner": "ALIGN_RATE",
                  "crossSeriesReducer": "REDUCE_SUM",
                  "groupByFields": []
                }
              }
            },
            "plotType": "LINE"
          }],
          "timeshiftDuration": "0s",
          "yAxis": {
            "label": "Changes",
            "scale": "LINEAR"
          }
        }
      }
    ]
  }
}
EOF
}
