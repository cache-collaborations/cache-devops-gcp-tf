# Outputs
output "audit_logs_bucket" {
  value = google_storage_bucket.audit_logs.name
}

output "audit_logs_sink" {
  value = google_logging_project_sink.audit_logs_sink.name
}