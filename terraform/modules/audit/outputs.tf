# Outputs
output "audit_logs_bucket" {
  value       = google_logging_project_bucket_config.audit_logs.bucket_id
  description = "Audit logs bucket name"
}

output "soc2_dashboard" {
  value       = google_monitoring_dashboard.soc2_dashboard.dashboard_json
  description = "SOC 2 compliance dashboard JSON"
}