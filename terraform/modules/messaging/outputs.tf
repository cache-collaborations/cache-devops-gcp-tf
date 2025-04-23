# terraform/modules/messaging/outputs.tf
output "topic_name" {
  value       = google_pubsub_topic.app_topic.name
  description = "The name of the Pub/Sub topic"
}

output "topic_id" {
  value       = google_pubsub_topic.app_topic.id
  description = "The ID of the Pub/Sub topic"
}

output "subscription_name" {
  value       = google_pubsub_subscription.app_subscription.name
  description = "The name of the Pub/Sub subscription"
}

output "subscription_id" {
  value       = google_pubsub_subscription.app_subscription.id
  description = "The ID of the Pub/Sub subscription"
}
