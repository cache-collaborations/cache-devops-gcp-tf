# terraform/modules/database/outputs.tf
output "instance_name" {
  value       = google_sql_database_instance.postgres.name
  description = "The name of the database instance"
}

output "private_ip" {
  value       = google_sql_database_instance.postgres.private_ip_address
  description = "The private IP address of the database instance"
}

output "connection_secret_id" {
  value       = google_secret_manager_secret.db_connection.secret_id
  description = "The Secret Manager secret ID containing the connection string"
}
