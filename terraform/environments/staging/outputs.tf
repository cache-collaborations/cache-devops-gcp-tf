# terraform/environments/staging/outputs.tf
output "vpc_name" {
  value       = module.networking.vpc_name
  description = "The name of the VPC"
}

output "kubernetes_cluster_name" {
  value       = module.kubernetes.cluster_name
  description = "The name of the GKE cluster"
}

output "kubernetes_cluster_endpoint" {
  value       = module.kubernetes.cluster_endpoint
  description = "The endpoint of the GKE cluster"
}

output "database_instance_name" {
  value       = module.database.instance_name
  description = "The name of the database instance"
}

output "database_connection_secret" {
  value       = module.database.connection_secret_id
  description = "The Secret Manager secret ID containing the database connection string"
}

output "pubsub_topic_name" {
  value       = module.messaging.topic_name
  description = "The name of the Pub/Sub topic"
}

output "kibana_endpoint" {
  value       = "http://${module.logging.kibana_ingress_host}:5601"
  description = "The endpoint of Kibana"
}
