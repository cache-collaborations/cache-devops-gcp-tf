# terraform/modules/messaging/main.tf
resource "google_pubsub_topic" "app_topic" {
  name    = "${var.environment}-${var.topic_name}"
  project = var.project_id

  message_storage_policy {
    allowed_persistence_regions = [
      "us-central1"
    ]
  }

  labels = {
    environment = var.environment
  }
}

resource "google_pubsub_subscription" "app_subscription" {
  name    = "${var.environment}-${var.topic_name}-subscription"
  topic   = google_pubsub_topic.app_topic.name
  project = var.project_id

  ack_deadline_seconds       = var.subscription_ack_deadline
  message_retention_duration = var.message_retention_duration

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  expiration_policy {
    ttl = "2592000s" # 30 days
  }

  labels = {
    environment = var.environment
  }
}

resource "google_pubsub_topic_iam_binding" "publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.app_topic.name
  role    = "roles/pubsub.publisher"
  members = [
    "serviceAccount:${var.project_id}-app-sa@${var.project_id}.iam.gserviceaccount.com"
  ]
}

resource "google_pubsub_subscription_iam_binding" "subscriber" {
  project      = var.project_id
  subscription = google_pubsub_subscription.app_subscription.name
  role         = "roles/pubsub.subscriber"
  members = [
    "serviceAccount:${var.project_id}-app-sa@${var.project_id}.iam.gserviceaccount.com"
  ]
}
